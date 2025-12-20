module my_addr::ananta_token_project {
    use std::signer; 
    use std::option;
    use std::string;
    
    use aptos_framework::object::{Self, ExtendRef};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, MutateMetadataRef};
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

}