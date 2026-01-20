module my_addr::ananta_token_project {
    use std::signer; 
    use std::option;
    use std::string;

    use aptos_framework::event;
    
    use aptos_framework::object::{Self, ExtendRef, Object};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, MutateMetadataRef, Metadata};
    use aptos_framework::primary_fungible_store;

    const TOKEN_SEED: vector<u8> = b"ANANTA";
    const TOKEN_SYMBOL: vector<u8> = b"ANANTA"; 

    struct TokenCapabilities has key {
        mint_ref: MintRef,
        transfer_ref: TransferRef,
        burn_ref: BurnRef,
        extend_ref: ExtendRef,
        mutate_ref: MutateMetadataRef,
    }
    #[event]
    struct TokenInitEvent has copy, drop, store {
        admin_addr: address,
        token_name: string::String,
        asset_metadata: Object<Metadata>,
    }

    public entry fun init_token(admin: &signer) {
        let ctor = object::create_named_object(admin, TOKEN_SEED);
        //Tạo FA
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor,
            option::none(),
            string::utf8(TOKEN_SEED),
            string::utf8(TOKEN_SYMBOL),
            6,
            string::utf8(b"https://coffee-objective-koala-978.mypinata.cloud/ipfs/bafkreihfamicuiqwtgei2aciopmuzt5hayqgixzrolpulk653gwfpe5r5i"),
            string::utf8(b"https://github.com/username/my-aptos-hackathon")
        );

        //Tạo ref cho FA 
        let mint_ref = fungible_asset::generate_mint_ref(&ctor);
        let transfer_ref = fungible_asset::generate_transfer_ref(&ctor);
        let burn_ref = fungible_asset::generate_burn_ref(&ctor);
        let extend_ref = object::generate_extend_ref(&ctor);
        let mutate_ref = fungible_asset::generate_mutate_metadata_ref(&ctor);

        //Lưu cap vào object 
        let object_signer = object::generate_signer(&ctor);
        move_to(&object_signer, TokenCapabilities {
            mint_ref,
            transfer_ref,
            burn_ref,
            extend_ref,
            mutate_ref
        });

        event::emit(TokenInitEvent {
            admin_addr: signer::address_of(admin),
            token_name: string::utf8(TOKEN_SEED),
            asset_metadata: object::object_from_constructor_ref<Metadata>(&ctor)
        })
    }

    //Mint token và gửi vào ví admin 
    //Chỉ admin được mint
    public entry fun mint(admin: &signer, amount: u64) acquires TokenCapabilities {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @my_addr, 1);

        let token_addr = object::create_object_address(&admin_addr, TOKEN_SEED);

        let token_capabities = borrow_global<TokenCapabilities>(token_addr);

        primary_fungible_store::mint(&token_capabities.mint_ref, admin_addr, amount);
    }

    public entry fun mint_to(admin: &signer, user: address, amount: u64) acquires TokenCapabilities {
        let admin_addr = signer::address_of(admin);
        
        // 1. Tính toán lại địa chỉ Kho (Object) từ Admin + Seed
        // (Phải dùng đúng Seed "ANANTA" như lúc init)
        let token_addr = object::create_object_address(&admin_addr, TOKEN_SEED);

        // 2. Kiểm tra xem Kho có tồn tại và chứa Cap không (Tìm ở token_addr)
        assert!(exists<TokenCapabilities>(token_addr), 10); 
        
        // 3. Kiểm tra amount
        assert!(amount > 0, 21);
        
        // 4. Mượn Cap từ địa chỉ Kho (token_addr)
        let token_capabities = borrow_global<TokenCapabilities>(token_addr);
        
        // 5. Mint cho User
        primary_fungible_store::mint(&token_capabities.mint_ref, user, amount);
    }

    #[test_only]
    use aptos_framework::account; // Dùng để tạo account giả lập

    //TEST CASE 1: KỊCH BẢN THÀNH CÔNG (HAPPY PATH)
    // Admin khởi tạo token và mint thành công cho Bob
    #[test(admin = @my_addr, user_bob = @0xB0B)]
    fun test_flow_mint_success(
        admin: &signer,
        user_bob: &signer
    ) acquires TokenCapabilities{
        //1. Setup môi trường giả lập 
        //Init token bởi admin 

        init_token(admin);

        let user_addr = signer::address_of(user_bob);
        let amount_mint = 1_000_000; // 1 token 

        //2 Action: Thực hiện hành động mint 
        mint_to(admin, user_addr, amount_mint);

        //3. Assert: Kiểm tra kết quả 
        //Cần lấy lại dịa chỉ của Metadata Object để check số dư 
        let admin_addr = signer::address_of(admin);
        let token_addr = object::create_object_address(&admin_addr, TOKEN_SEED);
        let metadata = object::address_to_object<Metadata>(token_addr);

        //Kiểm tra số dư của bob
        let balance_bob = primary_fungible_store::balance(user_addr, metadata);

        //Nếu số dư của bob bằng đúng số dư amount mint, thì test pass 
        assert!(balance_bob == amount_mint, 101);
    }

}

