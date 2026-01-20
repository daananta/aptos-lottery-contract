//Module này dùng để quản lý thử thách 
module my_addr::challenge {
    use std::signer;
    use std::string::String;
    use std::option::{Self, Option};
    use std::error;
    use std::vector;
    use std::bcs;

    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::simple_map::{Self, SimpleMap};
     
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Metadata, FungibleStore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::event;
    use aptos_framework::timestamp;

    use my_addr::game_types::{Self, ChallengeStatus, ChallengeCategory, SubmissionStatus, ScoringMode, RewardDistribution};
    use my_addr::userprofile;
    use my_addr::admin;
    //Pinata, irys, arweave, nft.storage 

    // --- CONSTANTS ---
    const MAX_JUDGES: u64 = 10;
    const MAX_CANDIDATES: u64 = 1000;
    const MAX_WINNERS: u64 = 20;


    // --- ERRORS ---
    ///Không có quyền 
    #[error]
    const E_NOT_AUTHORIZED: u64 = 1;  
    ///Trạng thái hiện tại không hợp lệ 
    #[error]
    const E_INVALID_STATE: u64 = 2;
    ///Đã quá thời hạn cho phép 
    #[error]
    const E_DEADLINE_PASSED: u64 = 3;
    ///Không đủ tiền/tài nguyên để thực hiện, số dư không đáp ứng yêu cầu 
    #[error]
    const E_INSUFFICIENT_FUND: u64 = 4;
    #[error]
    const E_CHALLENGE_NOT_FOUND: u64 = 5;
    #[error]
    const E_ALREADY_SUBMITTED: u64 = 6;
    #[error]
    const E_TOO_MANY_WINNERS: u64 = 7;
    #[error]
    const E_INVALID_REWARD: u64 = 8;
    ///Title quá dài
    #[error]
    const E_TITLE_TOO_LONG: u64 = 9;
    ///Metadata_uri quá dài
    #[error]
    const E_METADATA_URI_TOO_LONG: u64 = 10;
    /// Tổng phần trăm (100%)
    #[error]
    const TOTAL_PERCENT: u64 = 100;

    // --- EVENTS ---
    //Chỉ hiển thị thứ frontend cần nhất
    #[event] 
    struct ChallengeCreatedEvent has drop, store {
        challenge_id: u64,
        creator: address,
        title: String,
        reward_amount: u64,
        category: ChallengeCategory,
        end_at: u64,
        metadata_uri: String,
        challenge_address: address, //Thêm cái này để frontend dễ bắt sự kiện
    }

    //Event khi người dùng nộp bài
    #[event]
    struct SubmissionEvent has drop, store {
        challenge_id: u64,
        submitter: address,
        timestamp: u64,
    }

    #[event]
    struct VoteEvent has drop, store {
        challenge_id: u64,
        voter: address,
        candidate: address,
        timestamp: u64,
        score_val: u64,
    }

    struct ChallengeRegistry has key {
        next_challenge_id: u64,
        challenges: SmartTable<u64, address>,  // id -> object_address
        allowed_assets: vector<address>,
    }

    // Struct nhỏ để lưu tạm trong Leaderboard
    struct Candidate has store, drop, copy {
        addr: address,
        votes: u64,
    }

    // Key để tra cứu lịch sử vote
    struct VoteReceipt has copy, drop, store {
        voter: address,        // Ai vote?
        candidate: address,    // Vote cho bài thi nào? (dùng address của submitter làm ID bài thi)
    }

    //--- Struct Resource(Lưu trong object) ---
    struct Challenge has key {
        challenge_id: u64,
        status: ChallengeStatus,
        flags: u64,
        initial_reward: u64,
        reward_asset_store: Object<FungibleStore>,
        asset: Object<Metadata>,

        // Counters (Dùng Aggregator để update song song)
        total_sponsored: u64, 
        sponsor_count: u64,

        total_votes: u64, //Đánh giá độ hot

        // Submissions
        submissions: SmartTable<address, Submission>, //Submission là resource thường lưu vào account user
        submission_count: u64,

        // Người thắng cuộc (Ban đầu là Option::none())? vector empty
        top_candidates: vector<Candidate>,  // Hỗ trợ nhiều người thắng(tối đa 20)

        // Key: (Người vote + Bài thi) -> Value: bool (true)
        vote_records: SmartTable<VoteReceipt, bool>,

        //Thời gian và phase
        create_at: u64,
        start_at: u64,
        submission_deadline: u64, //Hạn chót nộp bài
        voting_deadline: u64, //Hạn chót chấm điểm 
        dispute_start_at: u64, //Thời gian bắt đầu khiếu nại

        // Versioning
        version: u8,
    }

    struct ChallengeConfig has key {
        challenge_id: u64,
        creator: address,

        title: String, //Không cần dùng hash vì ưu tiên tốc độ tải 
        metadata_uri: String, //Lưu trên Pinata
        category: ChallengeCategory,

        //Setting, Rules 
        scoring_mode: ScoringMode, //Cơ chế chấm điểm
        max_winners: u64, //Số người thắng tối đa
        distribution: RewardDistribution, //Cách phân phối phần thưởng

        // Dispute Settings
        dispute_duration: u64,  //Thời gian khiếu nại (vd 48h) 
        dispute_fee: u64,   

        // Judges (Thường ít thay đổi)
        judges: vector<address>,
        
        // Versioning
        version: u8,
        extend_ref: ExtendRef,
    }

    /// --- Submission Resource ---
    struct Submission has copy, store {
        challenge_id: u64,
        submitter: address,
        proof_uri: String,
        // proof_has: vector<u8> có vẻ không cần hash vì link trên pinata là hash 
        submitted_at: u64,
        status: SubmissionStatus,
        vote_count: u64,
        total_score: u64,
        is_hidden: bool,
    }


    fun init_module(admin: &signer) {
        move_to(admin, ChallengeRegistry{
            next_challenge_id: 0,
            challenges: smart_table::new(),
            allowed_assets: vector::empty(),
        })
    }

    ///Tạo thử thách
    public entry fun create_challenge(
        creator: &signer, //Người tạo
        //Tiêu đề
        title: String, //Tiêu đề 
        metadata_uri: String, //Link nội dung cụ thể
        //Luật chơi
        category_val: u8, //Loại thử thách 
        scoring_mode_val: u8, // Frontend gửi u8, loại chấm điểm 
        distribution_val: u8, //cách chia thưởng, frontend gửi
        max_winners: u64, //Số người thắng tối đa
        distribution_params: vector<u64>, //theo %
        //Thời gian
        start_delay: u64,         // Đảm bảo luôn lớn hơn 1 phút
        submission_duration: u64, // Thời gian cho nộp bài (VD: 7 ngày)
        voting_duration: u64,     // Thời gian cho chấm điểm (VD: 3 ngày)
        dispute_duration: u64,    // Thời gian cho khiếu nại (VD: 1 ngày)
        initial_reward: u64, // số tiền thưởng ban đầu
        asset_address: address, //Loại FA(frontend sẽ gửi tham số này)
        //Giám khảo 
        additional_judges: vector<address> //yêu cầu ít nhất 1 giám khảo, creator có thể thêm hoặc xóa giám khảo
    ) acquires ChallengeRegistry{
        let creator_addr = signer::address_of(creator);

        //Assert 
        assert!(title.length() <= 64, E_TITLE_TOO_LONG);
        assert!(metadata_uri.length() <= 256, E_METADATA_URI_TOO_LONG);
        assert!(distribution_params.length() == max_winners, 999);
        assert!(max_winners >= 1 && max_winners <= MAX_WINNERS, 999);
        assert!(start_delay >= 60, 999);
        assert!(additional_judges.length() >= 1 && additional_judges.length() <=20, 999);
        validate_distribution_params(distribution_val, distribution_params);

        let treasury_addr = admin::get_treasury_addr();
        let creation_fee = admin::get_creation_fee();
        let fee_bps = admin::get_platform_fee_bps();
        let dispute_fee = admin::get_dispute_fee();

        let category = game_types::u8_to_category(category_val);
        let scoring_mode = game_types::u8_to_scoring(scoring_mode_val);
        let distribution = game_types::u8_to_distribution(distribution_val, distribution_params);


        let challenge_registry = borrow_global_mut<ChallengeRegistry>(@my_addr);
        //Tăng id lên 1 lấy id
        challenge_registry.next_challenge_id += 1; //Tăng id lên 1
        let next_challenge_id = challenge_registry.next_challenge_id;

        //Lấy token mặc định 
        //Kiểm tra asset_address được truyền vào có đúng với allowed_assets không
        assert!(challenge_registry.allowed_assets.contains(&asset_address), 999);
        let asset_object = object::address_to_object<Metadata>(asset_address);

        //Lấy phí 
        if (creation_fee > 0 ) {
            primary_fungible_store::transfer(creator, asset_object, treasury_addr, creation_fee);
        };
        //Ép kiểu, không cần làm tròn số(admin sẽ mất vài đơn vị còn user sẽ có lợi vài đơn vị vd 9.995 sẽ thành 9)
        let platform_fee_amount = ((initial_reward as u128) * (fee_bps as u128) / 10000) as u64;
        let final_reward = initial_reward - platform_fee_amount;
        if (fee_bps > 0) {
            primary_fungible_store::transfer(creator, asset_object, treasury_addr, platform_fee_amount);
        };

        let challenge_object_ctor = object::create_object(creator_addr); //Vì đã lưu id => address ở ChallengeRegistry nên không cần create_named_object
        let challenge_object_signer = object::generate_signer(&challenge_object_ctor);
        let challenge_addr = object::address_from_constructor_ref(&challenge_object_ctor);

        smart_table::add(&mut challenge_registry.challenges, next_challenge_id, challenge_addr);

        //Tạo FungibleStore cho Object
        let store = primary_fungible_store::ensure_primary_store_exists(challenge_addr, asset_object);

        //Rút tiền từ Creator và nạp vào(đã trừ fee ở trên), vì phải nhắm tới store nên dùng hàm withdraw và deposit 
        if (final_reward > 0) {
            primary_fungible_store::transfer(creator, asset_object, challenge_addr, final_reward);
        };

        //Tính toán thời gian 
        let now = timestamp::now_seconds();
        let start_at = now + start_delay;
        let sub_deadline = start_at + submission_duration;
        let vote_deadline = sub_deadline + voting_duration;
        let dispute_start = vote_deadline; //Khiếu nại bắt đầu ngay khi kết thúc vote

        //tạo extend_ref
        let extend_ref = object::generate_extend_ref(&challenge_object_ctor);

        move_to(&challenge_object_signer, Challenge {
            challenge_id: next_challenge_id,
            status: ChallengeStatus::Upcoming,
            flags: 0,
            //Economy 
            initial_reward: final_reward,
            reward_asset_store: store,
            asset: asset_object,
            //Counters
            total_sponsored: 0,
            sponsor_count: 0,
            total_votes: 0,
            submissions: smart_table::new(),
            submission_count: 0,
            top_candidates: vector::empty(),
            vote_records: smart_table::new(),
            create_at: now,
            start_at,
            submission_deadline: sub_deadline,
            voting_deadline: vote_deadline,
            dispute_start_at: dispute_start,
            version: 1,       
        });

        move_to(&challenge_object_signer, ChallengeConfig {
            challenge_id: next_challenge_id,
            creator: creator_addr,
            title,
            metadata_uri,
            category,
            scoring_mode, //luật chơi
            max_winners,
            distribution, //Cách phân phối phần thưởng 
            dispute_duration, //thời gian khiếu nại 
            dispute_fee, //phí khiếu nại
            judges: additional_judges, //vector giám khảo 
            version: 1,
            extend_ref
        });

        userprofile::on_challenge_created(creator_addr, initial_reward, creation_fee); //đã cập nhật 4 field

        event::emit(ChallengeCreatedEvent{
            challenge_id: next_challenge_id,
            creator: creator_addr,
            title,
            reward_amount: final_reward,
            category,
            end_at: vote_deadline,
            metadata_uri,
            challenge_address: challenge_addr,
        });
    }

    //Nộp bài 
    public entry fun submit(
        user: &signer,
        challenge_id: u64,
        proof_uri: String,
    ) acquires Challenge, ChallengeRegistry {
        let user_addr = signer::address_of(user);
        let registry = borrow_global<ChallengeRegistry>(@my_addr);
        let now = timestamp::now_seconds();

        assert!(registry.challenges.contains(challenge_id), 999);
        let challenge_addr = *registry.challenges.borrow(challenge_id);

        let challenge = borrow_global_mut<Challenge>(challenge_addr);

        //Check thời gian xem có hợp lệ không
        assert!(challenge.start_at <= now && challenge.submission_deadline >= now, 999);
        //User chỉ được nộp 1 bài
        assert!(!challenge.submissions.contains(user_addr), 999);

        let submission = Submission {
            challenge_id,
            submitter: user_addr,
            proof_uri,
            submitted_at: now,
            status: SubmissionStatus::Pending,
            vote_count: 0,
            total_score: 0,
            is_hidden: false,
        };

        challenge.submissions.add(user_addr, submission);
        challenge.submission_count += 1;

        userprofile::update_joined_challenges(user_addr, challenge_id); //Thêm challenge vào danh sách tham gia và số lần tham gia 
        userprofile::update_reputation(user_addr, 100);

        event::emit(SubmissionEvent {
            challenge_id,
            submitter: user_addr,
            timestamp: now
        });
    }

    //Cần xử lý sybil và kiểm tra thời gian, chỉ vote sau khi hết thời gian nộp bài 
    public entry fun vote(sender: &signer, 
        challenge_id: u64, 
        candidate_addr: address, 
        score_val: u64
    ) acquires ChallengeRegistry, ChallengeConfig, Challenge {
        assert!(score_val <= 100, 999); //Check xem điểm hợp lệ không
        let sender_addr = signer::address_of(sender);
        let now = timestamp::now_seconds();
        
        let registry = borrow_global<ChallengeRegistry>(@my_addr);
        
        let challenge_addr = *registry.challenges.borrow(challenge_id);
        let challenge = borrow_global_mut<Challenge>(challenge_addr);
        let submission = challenge.submissions.borrow_mut(candidate_addr);

        //Check sender đã từng vote cho address ở challenge này chưa(đã kiểm tra sybil)
        let receipt_key = VoteReceipt{voter: sender_addr, candidate: candidate_addr};
        assert!(!challenge.vote_records.contains(receipt_key), 999);
        assert!(now >= challenge.submission_deadline && now <= challenge.voting_deadline, 999); //Check thời gian

        //Lấy Config để xem đang chơi ở chế độ nào
        let config = borrow_global<ChallengeConfig>(challenge_addr);

        let final_score_added: u64 = 0;

        if (config.scoring_mode == ScoringMode::JudgePick) {
            assert!(config.judges.contains(&sender_addr), 999); //Đảm bảo sender ở trong vector judges
            submission.total_score += score_val;
            final_score_added = score_val;
        } else if (config.scoring_mode == ScoringMode::CommunityVote) {
            submission.total_score += 1;
            final_score_added = 1;
        };

        submission.vote_count += 1;

        //Đánh dấu đã vote
        challenge.vote_records.add(receipt_key, true);

        //Cập nhật bảng xếp hạng 
        update_leaderboard(challenge, candidate_addr, submission.total_score);

        //Nâng reputation cho sender và candidate
        userprofile::update_reputation(candidate_addr, 9);
        userprofile::update_reputation(sender_addr, 11);

        event::emit(VoteEvent{
            challenge_id,
            voter: sender_addr,
            candidate: candidate_addr,
            timestamp: timestamp::now_seconds(),
            score_val: final_score_added,
        })
    }

    ///Sender có thể là giám khảo, khán giả(Hoặc dùng EventDrivenTx)
    public entry fun finalize_challenge(sender: &signer, challenge_id: u64) acquires Challenge, Challenge, ChallengeRegistry {
        //1. Lấy Challenge 
        let registry = borrow_global<ChallengeRegistry>(@my_addr);
        let challenge_addr = *registry.challenges.borrow(challenge_id);
        let challenge = borrow_global_mut<Challenge>(challenge_addr);   

        //2. Kiểm tra điều kiện
        let now = timestamp::now_seconds();
        assert!(now > challenge.voting_deadline, 999);
        assert!(challenge.status != ChallengeStatus::Completed, 999);

        //3. Lấy extend ref và signer
        let config = borrow_global<ChallengeConfig>(challenge_addr);
        let extend_ref = config.extend_ref;
        let challenge_signer = object::generate_signer_for_extending(&extend_ref);

        //4. Chia tiền
        if (config.distribution == RewardDistribution::RankedPercentage) {
            let 
        }

        //5. Cập nhật trạng thái


    }

    // Update leaderboard, hàm này được gọi mỗi khi giám khảo, khán giả gọi hàm vote
    fun update_leaderboard(
        challenge: &mut Challenge,
        candidate_addr: address,
        new_score: u64
    ) {
        let board = &mut challenge.top_candidates;

        //Bước 1: Xóa cũ 
        //Nếu thí sinh có trong bảng, xóa họ trước, xem họ như người mới với điểm với và tìm vị trí chèn lại 

        let (found, idx) = find_candidate_index(board, candidate_addr);

        if(found) {
            board.remove(idx);
        }; //Đã xóa

        //Bước 2: Chèn mới 
        //Duyệt từ trên xuống, người điểm cao nhất là idx 0 
        let i = 0;
        let len = vector::length(board);
        let inserted = false;

        while (i < len) {
            let current_candidate = board.borrow(i);

            //Nếu điểm cao hơn người đang đứng vị trí i, chèn trước họ(chiếm vị trí i)
            if(new_score > current_candidate.votes) {
                let c = Candidate {addr: candidate_addr, votes: new_score};
                board.insert(i, c);
                inserted = true;
                break; //đã chèn xong, thoát vòng lặp
            };
            i += 1;
        };

        //BƯỚC 3: XỬ LÝ NẾU CHƯA ĐƯỢC CHÈN ---
        // Nếu chạy hết vòng lặp mà chưa chèn (tức là điểm thấp hơn tất cả những người trong top hiện tại)
        // Nhưng bảng vẫn còn chỗ trống (chưa đủ 20 người) -> Nhét vào cuối bảng (bét bảng)
        if(!inserted && vector::length(board) < MAX_WINNERS) {
            let c = Candidate {addr: candidate_addr, votes: new_score};
            board.push_back(c);
        };

        // --- BƯỚC 4: CẮT GỌT (Trim) ---
        // Nếu sau khi chèn mà danh sách bị dài quá quy định (ví dụ thành 21 người)
        // -> Xóa người đứng cuối cùng (người điểm thấp nhất bị rớt đài)
        if (vector::length(board) > MAX_WINNERS) {
            vector::pop_back(board);
        };
    }

    /// Tìm xem candidate_addr có đang nằm trong Top 20 không
    /// Trả về (true, index) nếu tìm thấy, (false, 0) nếu không
    fun find_candidate_index(board: &vector<Candidate>, addr: address): (bool, u64) {
        let i = 0;
        let len = vector::length(board);
        while (i < len) {
            // So sánh địa chỉ
            if (vector::borrow(board, i).addr == addr) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }

    ///Thêm giám khảo 
    public fun add_judges(creator: &signer, challenge_id: u64, new_judges: vector<address>) acquires ChallengeRegistry, ChallengeConfig {
        let creator_addr = signer::address_of(creator);
        ///Xác định địa chỉ Challenge Object 
        let registry = borrow_global<ChallengeRegistry>(@my_addr);
        let challenge_addr = *registry.challenges.borrow(challenge_id);
        let challenge_obj = object::address_to_object<ChallengeConfig>(challenge_addr);
        assert!(object::is_owner(challenge_obj, creator_addr), 999); //kiểm tra xem creator có phải chủ sở hữu challenge không
        let config = borrow_global_mut<ChallengeConfig>(challenge_addr);
        config.judges.append(new_judges);
    }

    ///Xóa giám khảo
    public entry fun remove_judge_ordered(
        challenge: &mut ChallengeConfig, 
        judge_to_remove: address
    ) {
        let (found, i) = vector::index_of(&challenge.judges, &judge_to_remove);

        while (found) {
            // Dùng remove thường: Xóa xong các phần tử sau tự dồn lên
            vector::remove(&mut challenge.judges, i);

            // Tìm tiếp (Lưu ý: Vì các phần tử đã dồn lên, 
            // nên lần tìm tiếp theo vẫn sẽ chính xác)
            (found, i) = vector::index_of(&challenge.judges, &judge_to_remove);
        };
    }

    ///Thêm token chấp nhận vào danh sách
    public entry fun add_whitelist_asset(
        admin: &signer,
        asset: address,
    ) acquires ChallengeRegistry {
        assert!(@my_addr == signer::address_of(admin), 999); //chỉ admin mới được thêm 
        let challenge_registry = borrow_global_mut<ChallengeRegistry>(@my_addr);
        assert!(!challenge_registry.allowed_assets.contains(&asset), 999); //Kiểm tra xem đã tồn tại trong vector chưa
        challenge_registry.allowed_assets.push_back(asset);
    }

    ///Trả về danh sách giám khảo cho frontend
    #[view]
    public fun get_judges(challenge_id: u64): vector<address> acquires ChallengeRegistry, ChallengeConfig {
        let registry = borrow_global<ChallengeRegistry>(@my_addr);
        let challenge_addr = *registry.challenges.borrow(challenge_id);

        let config = borrow_global<ChallengeConfig>(challenge_addr);
        config.judges
    }

    ///Trả về bool xem có đúng là giám khảo không để frontend hiện ra nút chấm
    #[view]
    public fun is_judge(judge: address, challenge_id: u64): bool acquires ChallengeRegistry, ChallengeConfig {
        let registry = borrow_global<ChallengeRegistry>(@my_addr);
        let challenge_addr = *registry.challenges.borrow(challenge_id);

        let config = borrow_global<ChallengeConfig>(challenge_addr);
        config.judges.contains(&judge)
    }

    ///Kiểm tra xem tỉ lệ phần thưởng của danh sách winners có đúng không
    fun validate_distribution_params(
        distribution_val: u8,
        distribution_params: vector<u64>,
    ) {
        // 1. Kiểm tra Type = RankedPercentage (1)
        if (distribution_val == 1) {
            let sum: u64 = 0;
            let i = 0;
            let len = distribution_params.length();

            // Bắt buộc phải có ít nhất 1 phần trăm
            assert!(len > 0, error::invalid_argument(999));

            while (i < len) {
                let val = *vector::borrow(&distribution_params, i);
                
                // Validate từng phần tử
                assert!(val > 0 && val <= 100, error::invalid_argument(999));
                
                sum = sum + val;
                i = i + 1;
            };

            // Validate tổng
            assert!(sum == 100, error::invalid_argument(999));
        };
    }
}