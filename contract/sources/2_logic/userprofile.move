module my_addr::userprofile {
    use std::signer;
    use std::string::{Self, String};
    use std::error;
    
    use aptos_framework::event;
    use aptos_framework::smart_table::{Self, SmartTable};
    use aptos_framework::timestamp;
    use aptos_framework::simple_map::{Self, SimpleMap};

    
    use my_addr::game_types::{Self, ServerRegion, RankLevel, SocialType};
    use my_addr::challenge::{Self, Submission};

    // --- Constants Internal (Chỉ module này cần biết) ---
    const USER_SCHEMA_VERSION: u8 = 1;

    // Error Codes
    #[error]
    const E_ALREADY_INITIALIZED: u64 = 1;
    #[error]
    const E_USER_NOT_INITIALIZED: u64 = 2;
    #[error]
    const E_NAME_TOO_LONG: u64 = 3;
    #[error]
    const E_BIO_TOO_LONG: u64 = 4;
    #[error]
    const E_INVALID_SOCIAL_TYPE: u64 = 5; // Vẫn giữ ở đây để validate input
    #[error]
    const E_INVALID_UID: u64 = 6;

    // --- UserProfile update fields (bitmask) ---
    // Move 2.0 đã hỗ trợ tính toán const
    const PROFILE_DISPLAY_NAME: u64 = 1 << 0;     
    const PROFILE_BIO: u64          = 1 << 1;      
    const PROFILE_AVATAR: u64       = 1 << 2;      
    const PROFILE_SOCIAL: u64       = 1 << 3;      
    const PROFILE_FLAGS: u64        = 1 << 4;     
    const GAME_ACCOUNT_UID: u64     = 1 << 5;     
    const GAME_ACCOUNT_SERVER: u64  = 1 << 6;     

    // --- Events ---
    #[event]
    struct UserProfileUpdateEvent has store, drop {
        user: address,
        update_fields: u64,
        updated_at:  u64,
        version: u8,
    }

    #[event]
    struct GameAccountUpdateEvent has drop, store {
        user: address,
        update_fields: u64,
        updated_at: u64,
        version: u8,
    }

    #[event]
    struct UserInitializedEvent has drop, store {
        user: address,
        created_at: u64,
        version: u8,
    }

    // --- Structs (Resources) ---

    struct UserProfile has key {
        display_name: String,
        bio: String,
        avatar_url: String,
        social_links: SimpleMap<SocialType, String>,
        created_at: u64,
        updated_at: u64,
        version: u8,
        flags: u64,
    }

    struct UserStats has key {
        reputation: u64,        // Điểm uy tín tổng hợp của user (ảnh hưởng rank & trust)
        bounties_won: u64,      // Số bounty đã thắng (claim thành công)
        bounties_joined: u64,   // Tổng số bounty đã tham gia
        total_earned: u64,      // Tổng token kiếm được từ hệ thống
        disputes_lost: u64,     // Số khiếu nại bị xử thua
        bounties_created: u64,  // Số bounty user đã tạo
        total_spent: u64,       // Tổng token đã chi (tạo bounty, fee, penalty)
        rank_level: RankLevel,  // Cấp bậc hiện tại (Bronze/Silver/Gold/...)
        season_points: u64,     // Điểm theo mùa (reset mỗi season, dùng leaderboard)
        last_active_at: u64,    // Thời điểm hoạt động gần nhất (timestamp giây)
        version: u8,            // Version struct (phục vụ upgrade/migration)
        flags: u64,             // Bit flags trạng thái (ban, verified, vip,...)
    }

    struct GameAccount has key {
        // 👇 Dùng Enum ServerRegion (đã import)
        server_region: ServerRegion, 
        uid: String,
        is_main: bool,
        verified: bool,
        linked_at: u64,
    }   

    struct PlayerPortfolio has key {
        // Map từ Challenge ID -> Submission
        submissions: SmartTable<u64, Submission>, 
        total_participated: u64,
        total_wins: u64,
    }
    
    // =============================================================================
    // FUNCTIONS
    // =============================================================================

    public entry fun initialize_user(user: &signer) {
        let user_addr = signer::address_of(user);
        assert!(!exists<UserProfile>(user_addr), error::invalid_state(E_ALREADY_INITIALIZED));

        let now = timestamp::now_seconds();
        move_to(user, UserProfile{
            display_name: string::utf8(b""),
            bio: string::utf8(b""),
            avatar_url: string::utf8(b""),
            social_links: simple_map::new(),
            created_at: now,
            updated_at: now,
            version: USER_SCHEMA_VERSION,
            flags: 0,
        });

        move_to(user, UserStats {
            reputation: 0,
            bounties_won: 0,
            bounties_joined: 0,
            total_earned: 0,
            disputes_lost: 0,
            bounties_created: 0,
            total_spent: 0,
            // 👇 Khởi tạo bằng Enum
            rank_level: RankLevel::Bronze, 
            season_points: 0,
            last_active_at: now,
            version: USER_SCHEMA_VERSION,
            flags: 1 // Default flag logic
        });

        move_to(user, GameAccount{
            // 👇 Khởi tạo bằng Enum
            server_region: ServerRegion::Unknown,
            uid: string::utf8(b""),
            is_main: true,
            verified: false,
            linked_at: 0,
        });

        event::emit(UserInitializedEvent{
            user: user_addr,
            created_at: now,
            version: USER_SCHEMA_VERSION,
        });
    }

    // ... (Hàm update_profile_basic giữ nguyên logic, không đổi gì) ...
    public entry fun update_profile_basic(
        user: &signer,
        display_name: String,
        bio: String,
        avatar_url: String
    ) acquires UserProfile {
        let user_addr = signer::address_of(user);
        assert_initialized(user_addr);
        let profile = borrow_global_mut<UserProfile>(user_addr);
        
        // ... (Validate length giữ nguyên) ...
        assert!(display_name.length() <= 32, error::invalid_argument(E_NAME_TOO_LONG));
        assert!(bio.length() <= 1000, error::invalid_argument(E_BIO_TOO_LONG));

        let update_fields: u64 = 0; // Thêm mut vì Move 2.0 cần khai báo mutable rõ ràng

        if (!display_name.is_empty()) {
            profile.display_name = display_name;
            update_fields |= PROFILE_DISPLAY_NAME;
        };
        if (!bio.is_empty()) {
            profile.bio = bio;
            update_fields |= PROFILE_BIO;
        };
        if (!avatar_url.is_empty()) {
            profile.avatar_url = avatar_url;
            update_fields |= PROFILE_AVATAR;
        };

        profile.updated_at = timestamp::now_seconds();
        event::emit(UserProfileUpdateEvent {
            user: user_addr,
            update_fields,
            updated_at: profile.updated_at,
            version: profile.version,
        })
    }

    public entry fun update_social_link(
        user: &signer,
        kind_code: u8, // Frontend vẫn gửi số 1, 2, 3...
        value: String,
    ) acquires UserProfile {
        let user_addr = signer::address_of(user);
        assert_initialized(user_addr);

        // 1. Chuyển đổi u8 sang Enum bằng hàm Helper
        let social_type = game_types::u8_to_social(kind_code);
        
        // 2. Kiểm tra nếu là Unknown thì báo lỗi
        assert!(social_type != SocialType::Unknown, error::invalid_argument(E_INVALID_SOCIAL_TYPE));

        let profile = borrow_global_mut<UserProfile>(user_addr);

        // 3. Upsert vào Map (Map bây giờ Key là SocialType)
        profile.social_links.upsert(social_type, value);
        profile.updated_at = timestamp::now_seconds();

        event::emit(UserProfileUpdateEvent{
            user: user_addr,
            update_fields: PROFILE_SOCIAL,
            updated_at: timestamp::now_seconds(),
            version: USER_SCHEMA_VERSION
        });
    }

    public entry fun remove_social_link(
        user: &signer,
        kind_code: u8,
    ) acquires UserProfile {
        let user_addr = signer::address_of(user);
        assert_initialized(user_addr);
        
        // Chuyển đổi sang Enum để tìm trong Map
        let social_type = game_types::u8_to_social(kind_code);
        
        let profile = borrow_global_mut<UserProfile>(user_addr);

        if (profile.social_links.contains_key(&social_type)) {
            profile.social_links.remove(&social_type);
            profile.updated_at = timestamp::now_seconds();

            event::emit(UserProfileUpdateEvent{
                user: user_addr,
                update_fields: PROFILE_SOCIAL,
                updated_at: timestamp::now_seconds(),
                version: USER_SCHEMA_VERSION
            })
        }
    }

    public entry fun update_game_account(
        user: &signer,
        server_region: u8,
        uid: String,
        is_main: bool,
    ) acquires GameAccount {
        let user_addr = signer::address_of(user);
        assert_initialized(user_addr);

        let game_account = borrow_global_mut<GameAccount>(user_addr);
        
        // 👇 Dùng Helper function từ game_types để code gọn gàng
        let new_region = game_types::u8_to_region(server_region);

        let update_fields: u64 = 0;
       
        if (game_account.server_region != new_region) {
            game_account.server_region = new_region; // Cập nhật luôn
            update_fields |= GAME_ACCOUNT_SERVER;
        };

        if (game_account.uid != uid) {
            game_account.uid = uid; // Cập nhật luôn
            update_fields |= GAME_ACCOUNT_UID;
        };
        
        game_account.is_main = is_main;
        game_account.verified = false;
        game_account.linked_at = timestamp::now_seconds();

        event::emit(GameAccountUpdateEvent{
            user: user_addr,
            update_fields,
            updated_at: timestamp::now_seconds(),
            version: USER_SCHEMA_VERSION,
        })
    }

    public(package) fun verified_game_account(user_addr: address) acquires GameAccount {
        assert_initialized(user_addr);
        let game_account = borrow_global_mut<GameAccount>(user_addr);
        game_account.verified = true;
    }

    //Nâng chỉ số bounties_created lên khi gọi hàm create_challenge 
    public(package) fun update_bounties_created(user_addr: address) acquires UserStats {
        let user_stats = borrow_global_mut<UserStats>(user_addr);
        user_stats.bounties_created += 1;
        user_stats.last_active_at = timestamp::now_seconds();
    }

    //Nâng chỉ số uy tín 
    public(package) fun update_reputation(user_addr: address, delta: u64) acquires UserStats {
        let user_stats = borrow_global_mut<UserStats>(user_addr);
        user_stats.reputation += delta;
        user_stats.last_active_at = timestamp::now_seconds();
    }

    public(package) fun update_total_spent(user_addr: address, delta: u64) acquires UserStats {
        let user_stats = borrow_global_mut<UserStats>(user_addr);
        user_stats.total_spent += delta;
        user_stats.last_active_at = timestamp::now_seconds();
    }

    ///Cập nhật lúc tạo challenge, truy cập Global Storage 1 lần để cập nhật 4 field trong resource UserStats 
    public(package) fun on_challenge_created(user_addr: address, initial_reward: u64, creation_fee: u64) acquires UserStats {
        let user_stats = borrow_global_mut<UserStats>(user_addr);
        user_stats.bounties_created += 1;
        let total_spent = initial_reward + creation_fee;
        let reputation = total_spent / 100_000; //Mỗi 1 Ananta được 10 điểm uy tín 
        user_stats.total_spent += total_spent;
        user_stats.reputation += reputation;
        user_stats.last_active_at = timestamp::now_seconds();
    }
    
    // View Functions
    #[view]
    public fun exists_user(user: address): bool {
        exists<UserProfile>(user)
    }

    //Hàm nội bộ
    fun assert_initialized(addr: address) {
        assert!(exists<UserProfile>(addr), error::invalid_state(E_USER_NOT_INITIALIZED));
    }

    
}