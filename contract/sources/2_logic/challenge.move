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
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleStore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::aggregator_v2::{Self, Aggregator};
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

        // Submissions
        submissions: SmartTable<address, bool>, //Submission là resource thường lưu vào account user
        submission_count: u64,

        // Người thắng cuộc (Ban đầu là Option::none())
        top_candidates: vector<Candidate>,  // Hỗ trợ nhiều người thắng

        //Thời gian và phase
        create_at: u64,
        start_at: u64,
        submission_deadline: u64,
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
        platform_fee_bps: u64, //Phí nền tảng(2,5%)
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
        verified_by: Option<address>,
        verified_at: u64,
    }


    fun init_module(admin: &signer) {
        move_to(admin, ChallengeRegistry{
            next_challenge_id: 0,
            challenges: smart_table::new(),
            allowed_assets: vector::empty(),
        })
    }

    public entry fun create_challenge(
        creator: &signer, //Người tạo
        //Tiêu đề
        title: String, //Tiêu đề 
        metadata_uri: String, //Link nội dung cụ thể
        //Luật chơi
        category_val: u8, //Loại thử thách 
        scoring_mode_val: u8, // Frontend gửi u8, loại chấm điểm 
        distribution_val: u8, //cách chia thưởng
        max_winners: u64, //Số người thắng tối đa
        distribution_params: vector<u64>, //theo %
        //Thời gian
        start_delay: u64,         // 0 nếu muốn bắt đầu luôn. >0 nếu muốn lên lịch (Upcoming)
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
        assert!(additional_judges.length() >= 1 && additional_judges.length() <=20, 999);
        validate_distribution_params(distribution_val, distribution_params);

        let treasury_addr = admin::get_treasury_addr();
        let creation_fee = admin::get_creation_fee();
        let fee_bps = admin::get_platform_fee_bps();
        let dispute_fee = admin::get_dispute_fee();

        let category = game_types::u8_to_category(category_val);
        let scoring_mode = game_types::u8_to_scoring(scoring_mode_val);
        let distribution = game_types::u8_to_distribution(distribution_val);


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
            status: ChallengeStatus::Active,
            flags: 0,
            //Economy 
            initial_reward: final_reward,
            reward_asset_store: store,
            asset: asset_object,
            //Counters
            total_sponsored: 0,
            sponsor_count: 0,
            submissions: smart_table::new(),
            submission_count: 0,
            top_candidates: vector::empty(),
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
            platform_fee_bps: fee_bps,
            scoring_mode, //luật chơi
            max_winners,
            distribution, //Cách phân phối phần thưởng 
            dispute_duration, //thời gian khiếu nại 
            dispute_fee, //phí khiếu nại
            judges: additional_judges, //vector giám khảo 
            version: 1,
            extend_ref
        });

        userprofile::on_challenge_created(creator_addr, initial_reward, creation_fee);

        event::emit(ChallengeCreatedEvent{
            challenge_id,
            creator: creator_addr,
            title,
            reward_amount: final_reward,
            category,
            end_at: vote_deadline,
            metadata_uri,
            challenge_address: challenge_addr,
        });
    }

    public fun add_judges(creator: &signer, challenge_id: u64, ) acquires ChallengeRegistry, ChallengeConfig {
        ///Xác định địa chỉ Challenge Object 
        let registry = borrow_global<ChallengeRegistry>(@my_addr);
        let challenge_addr = *registry.challenges.borrow(challenge_id);
        assert!(object::is_owner())
        let config = borrow_global_mut<ChallengeConfig>(challenge_addr);

        
    }

    public entry fun add_whitelist_asset(
        admin: &signer,
        asset: address,
    ) acquires ChallengeRegistry {
        assert!(@my_addr == signer::address_of(admin), 999); //chỉ admin mới được thêm 
        let challenge_registry = borrow_global_mut<ChallengeRegistry>(@my_addr);
        assert!(challenge_registry.allowed_assets.contains(&asset), 999); //Kiểm tra xem đã tồn tại trong vector chưa
        challenge_registry.allowed_assets.push_back(asset);
    }

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