module my_addr::game_types {
    use std::string::String;


    ///Lỗi không có scoring_mode hoặc sai
    const E_INVALID_SCORING_MODE: u64 = 1;
    ///Lỗi không có category(thể loại thử thách)
    const E_INVALID_CATEGORY_MODE: u64 = 2;
    ///Lỗi không có distribution(cách chia tiền)
    const E_INVALID_DISTRIBUTION_MODE: u64 = 3;
    

    
    // --- 1. Social Types ---
    // Chuyển từ const u8 sang Enum để dùng làm Key trong SimpleMap
    public enum SocialType has copy, drop, store {
        Twitter,
        Github,
        Telegram,
        Discord,
        Youtube,
        Facebook,
        Unknown // Dùng khi input không hợp lệ
    }

    // --- 2. Server Region ---
    public enum ServerRegion has copy, drop, store {
        Unknown,
        Asia,
        NA,     // North America
        EU,     // Europe
        SEA     // South East Asia
    }

    // --- 3. Rank Level ---
    public enum RankLevel has copy, drop, store {
        Bronze,
        Silver,
        Gold,
        Platinum
    }

    //Chờ EventDriventx
    public enum ChallengeStatus has copy, drop, store {
        Upcoming, //Đã tạo, chưa bắt đầu
        Active,     // Đang diễn ra (Bình thường)
        Completed,   // Đã kết thúc, chưa trao giải
        Settled,     // Đã trao thưởng xong (final)
        Cancelled,  // Admin hủy kèo (Dừng lại)
    }

    public enum ChallengeCategory has copy, drop, store {
        // 1. Đua tốc độ (VD: Phá đảo Elden Ring dưới 2 tiếng)
        Speedrun,      
        
        // 2. Kỹ năng PvP (VD: Thắng 10 trận CS:GO liên tiếp, Leo rank Thách đấu)
        PvP_Combat,    
        
        // 3. Săn thành tựu (VD: Giết Boss ẩn, Sưu tầm đủ 100 món đồ)
        Achievement,   
        
        // 4. Sáng tạo nội dung (VD: Làm video highlight, Vẽ fanart, Cosplay)
        ContentCreation, 
        
        // 5. Viết hướng dẫn (VD: Viết bài hướng dẫn build đồ, Mẹo qua màn)
        Strategy_Guide, 
        
        // 6. Sự kiện cộng đồng (VD: Tổ chức giải đấu ao làng, Mời bạn bè)
        CommunityEvent,

        //7 Tìm bug 
        BugBounty,

        //8 Khác 
        Other,
    }

    // Định nghĩa luật chơi
    public enum ScoringMode has copy, drop, store {
        // Mode 1: Giám khảo toàn quyền (Verified -> Judge Pick)
        JudgePick,      
        
        // Mode 2: Cộng đồng bầu chọn (Verified -> Voting -> Top Vote Wins)
        CommunityVote,
    }

    public enum SubmissionStatus has copy, drop, store {
        Pending,                // Đang chờ
        Approved,               // Đã duyệt
        
        // Rejected chứa luôn lý do (String). 
        // Đây là điều u8 không bao giờ làm được.
        Rejected(String),       
        
        Disputed                // Đang khiếu nại (mở rộng sau này dễ dàng)
    }

    public enum RewardDistribution has copy, drop, store {
        // Kiểu 1: Chia theo phần trăm thứ hạng (Esport / Hackathon)
        // Ví dụ: Vector [5000, 3000, 2000] -> Top 1: 50%, Top 2: 30%, Top 3: 20%.
        // Tổng phải <= 10000 (100%).
        RankedPercentage(vector<u64>), //kèm vector

        // Kiểu 2: Chia đều quỹ thưởng (Community Event)
        // Ví dụ: Quỹ 100 APT, có 4 người thắng -> Mỗi người 25 APT.
        EqualShare, 
    }


    // --- HELPER FUNCTIONS ---
    // Giúp chuyển đổi từ số (Frontend gửi lên) sang Enum (Logic Move)

    public fun u8_to_social(kind: u8): SocialType {
        if (kind == 1) { SocialType::Twitter }
        else if (kind == 2) { SocialType::Github }
        else if (kind == 3) { SocialType::Telegram }
        else if (kind == 4) { SocialType::Discord }
        else if (kind == 5) { SocialType::Youtube }
        else if (kind == 6) { SocialType::Facebook }
        else { SocialType::Unknown }
    }

    public fun u8_to_region(code: u8): ServerRegion {
        if (code == 1) { ServerRegion::Asia }
        else if (code == 2) { ServerRegion::NA }
        else if (code == 3) { ServerRegion::EU }
        else if (code == 4) { ServerRegion::SEA }
        else { ServerRegion::Unknown }
    }

    public fun u8_to_scoring(code: u8): ScoringMode {
        if(code == 1) {ScoringMode::CommunityVote}
        else if(code == 2) {ScoringMode::JudgePick}
        else{
             abort E_INVALID_SCORING_MODE
        }
    }

    public fun u8_to_category(code: u8): ChallengeCategory {
        if(code == 1) {ChallengeCategory::Speedrun}
        else if(code == 2) {ChallengeCategory::PvP_Combat}
        else if(code == 3) {ChallengeCategory::Achievement}
        else if(code == 4) {ChallengeCategory::ContentCreation}
        else if(code == 5) {ChallengeCategory::Strategy_Guide}
        else if(code == 6) {ChallengeCategory::CommunityEvent}
        else if(code == 7) {ChallengeCategory::BugBounty}
        else if(code == 8) {ChallengeCategory::Other}
        else { abort E_INVALID_CATEGORY_MODE }
    }

    // Trong game_types.move
    public fun u8_to_distribution(code: u8, params: vector<u64>): RewardDistribution {
        if (code == 1) {
            // Case 1: RankedPercentage
            // Nhét vector params vào trong Enum
            RewardDistribution::RankedPercentage(params)
        } 
        else if (code == 2) {
            // Case 2: EqualShare
            // Params bị thừa ở đây, nhưng vì vector<u64> có drop nên Move tự hủy nó.
            RewardDistribution::EqualShare
        } 
        else {
            abort E_INVALID_DISTRIBUTION_MODE
        }
    }
}       