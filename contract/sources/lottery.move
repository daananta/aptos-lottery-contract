module my_addr::lottery {
    use std::signer;

    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::randomness;
    use aptos_framework::timestamp;

    ///Lỗi chưa đủ tiền mua vé
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    ///Lỗi: Chưa đến giờ quay thưởng 
    const E_NOT_YET_TIME: u64 = 2;
    ///Lỗi: Không phải admin 
    const E_NOT_ADMIN: u64 = 3;

    const LOTTERYGAMESEED: vector<u8> = b"LOTTERYGAMESEED";


    struct LotteryGame has key {
        price_ticket: u64, //Giá vé 
        prize_pool: u64, //Tổng số tiền đã tích lũy
        players: SmartVector<address>,
        asset_metadata: Object<Metadata>,
        epoch: u64, // Thời gian kết thúc 1 vòng, tính bằng giây
        last_time: u64, //Lần quay số cuối cùng của lần trước 
        extend_ref: ExtendRef,
    }

    /// Hàm khởi tạo game 
    public entry fun init_game(admin: &signer, asset_metadata: Object<Metadata>) {
        let constructor_ref = object::create_named_object(admin, LOTTERYGAMESEED);
        let object_signer = object::generate_signer(&constructor_ref);
        let extend_ref = object::generate_extend_ref(&constructor_ref);

        move_to(&object_signer, LotteryGame {
            price_ticket: 1_000_000,
            prize_pool: 0,
            players: smart_vector::new(),
            asset_metadata,
            epoch: 10,
            last_time: 0,
            extend_ref,
        });

    }

    ///Admin set asset cho phép cùng lúc set thời gian quay
    public entry fun set_asset(admin: &signer, asset_metadata: Object<Metadata>) acquires LotteryGame {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @my_addr, E_NOT_ADMIN);

        let lottery_game = borrow_global_mut<LotteryGame>(get_game_address(admin_addr));
        lottery_game.asset_metadata = asset_metadata;
        lottery_game.last_time = timestamp::now_seconds();
    }

    ///Hàm mua vé, amount ở đây là số vé
    public entry fun buy_ticket(user: &signer, amount: u64) acquires LotteryGame {
        let user_addr = signer::address_of(user);

        //1. Lấy địa chỉ của Game object 
        let game_addr = get_game_address(@my_addr);

        //Kiểm tra số lượng vé hợp lệ 
        assert!(amount > 0, 4);

        //2. Mượn dữ liệu Game để sửa đổi 
        let lottery_game = borrow_global_mut<LotteryGame>(game_addr);

        //3. Tính tổng tiền: Số vé * giá vé 
        let total_cost = amount * lottery_game.price_ticket;

        //4. Trừ tiền: Chuyển từ User => Vào ví của Game 
        primary_fungible_store::transfer(
            user,
            lottery_game.asset_metadata,
            game_addr,
            total_cost,
        );

        //Cập nhật bể thưởng(số hiển thị)
        lottery_game.prize_pool += total_cost;

        //Vòng lặp, lưu tên người mua vào danh sách 
        let i:u64 = 0;
        while( i < amount) {
            //Đẩy địa chỉ user vào SmartVector 
            smart_vector::push_back(&mut lottery_game.players, user_addr);
            //Tăng biến đếm 
            i = i + 1;
        }
    }

    //Hàm quay số trúng thưởng, chỉ quay khi 18h trở đi 
    #[randomness]
    entry fun pick_winner(user: &signer) acquires LotteryGame {
        let _user_addr = signer::address_of(user);
        let game_addr = get_game_address(@my_addr);
        let lottery_game = borrow_global_mut<LotteryGame>(game_addr);

        //1. Kiểm tra điều kiện thời gian 
        //epoch ở đây hiểu là timestamp lần quay kế tiếp 
        let now = timestamp::now_seconds();
        assert!(now > lottery_game.last_time + lottery_game.epoch, E_NOT_YET_TIME);

        // 2. Kiểm tra có người chơi không 
        let total_tickets = smart_vector::length(&lottery_game.players);
        assert!(total_tickets > 0, E_INSUFFICIENT_BALANCE);

        //3 --RANDOMNESS MAGIC 
        //Sinh số ngẫu nhiên từ 0 tới (tổng vé - 1);
        // Ví dụ 10 vé thì random từ 0-9 
        let random_index = randomness::u64_range(0, total_tickets);

        //4 Lấy địa chỉ người thắng 
        let winner_addr = *smart_vector::borrow(&lottery_game.players, random_index);

        //5 Chuyển tiền thưởng 
        //Vì tiền nằm trong Game Object, ta cần tạo Signer từ ExtendRef  
        let game_signer = object::generate_signer_for_extending(&lottery_game.extend_ref);

        primary_fungible_store::transfer(
            &game_signer,
            lottery_game.asset_metadata,
            winner_addr,
            lottery_game.prize_pool
        );

        //6 Reset game cho vòng sau 
        lottery_game.prize_pool = 0;
        lottery_game.last_time = now;

        // Xóa danh sách người chơi để bắt đầu mới
        // Lưu ý: Nếu danh sách quá dài (>10k), vòng lặp này có thể hết Gas. 
        // Trong thực tế sẽ dùng kỹ thuật khác (tạo vector mới), nhưng ở mức cơ bản thì dùng cách này:
        while (!smart_vector::is_empty(&lottery_game.players)) {
            smart_vector::pop_back(&mut lottery_game.players);
        };
    }

    #[view]
    public fun get_game_address(creator: address): address {
        object::create_object_address(&creator, LOTTERYGAMESEED)
    }
}