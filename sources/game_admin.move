module aptos_arcade::game_admin {

    use std::signer;
    use std::vector;
    use std::string::String;
    use std::option::Option;

    use aptos_std::type_info;

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::object::{Self, ConstructorRef};

    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_token_objects::royalty::Royalty;

    // error codes

    /// when the signer is not the game admin
    const ESIGNER_NOT_ADMIN: u64 = 0;

    /// when calling initialize with a `GameType` that has already been initialized
    const EGAME_ACCOUNT_ALREADY_INITIALIZED: u64 = 1;

    /// when calling a function that requires the game account for a `GameTyoe` to be initialized, but it is not
    const EGAME_ACCOUNT_NOT_INITIALIZED: u64 = 2;

    // constants

    const ACCOUNT_SEED_TEMPLATE: vector<u8> = b" Account";

    // structs

    /// holds the `SignerCapability` for the game admin account
    struct GameAdmin<phantom GameType> has key {
        signer_cap: SignerCapability
    }

    /// used to access game admin functions
    struct GameAdminCapability<phantom GameType> has drop {}

    /// used to access player functions
    struct PlayerCapability<phantom GameType> has drop {
        player_address: address
    }

    // public functions

    /// initializes the game admin for the given `GameType`
    /// `game_admin` - must be the deployer of the `GameType` struct
    /// `witness` - ensures that the `GameType` struct is the same as the one that was deployed
    public fun initialize<GameType: drop>(game_admin: &signer, _witness: GameType): GameAdminCapability<GameType> {
        assert_game_admin_not_initialized<GameType>();
        assert_signer_is_game_admin<GameType>(game_admin);
        let (_, signer_cap) = account::create_resource_account(game_admin, get_game_account_seed<GameType>());
        move_to(game_admin, GameAdmin<GameType> { signer_cap });
        GameAdminCapability<GameType> {}
    }

    /// creates a collection for the given `GameType` under the game admin resource account
    /// `game_admin_cap` - must be a game admin capability for the given `GameType`
    /// `description` - description of the collection
    /// `name` - name of the collection
    /// `royalty` - royalty of the collection
    /// `uri` - uri of the collection
    public fun create_collection<GameType>(
        game_admin_cap: &GameAdminCapability<GameType>,
        descripion: String,
        name: String,
        royalty: Option<Royalty>,
        uri: String
    ): ConstructorRef acquires GameAdmin {
        let game_account_signer = get_game_account_signer_admin(game_admin_cap);
        collection::create_unlimited_collection(
            &game_account_signer,
            descripion,
            name,
            royalty,
            uri
        )
    }

    /// mints a token for `collection_name` for the given `GameType` under the game admin resource account
    /// `game_admin_cap` - must be a game admin capability for the given `GameType`
    /// `collection_name` - name of the collection
    /// `token_description` - description of the token
    /// `token_name` - name of the token
    /// `royalty` - royalty of the token
    /// `uri` - uri of the token
    public fun mint_token_game_admin<GameType>(
        game_admin_cap: &GameAdminCapability<GameType>,
        collection_name: String,
        token_description: String,
        token_name: String,
        royalty: Option<Royalty>,
        uri: String
    ): ConstructorRef acquires GameAdmin {
        let game_account_signer = get_game_account_signer_admin(game_admin_cap);
        token::create_from_account(
            &game_account_signer,
            collection_name,
            token_description,
            token_name,
            royalty,
            uri
        )
    }

    /// mints a token for `collection_name` for the given `GameType` under the player resource account
    /// `player_cap` - must be a player capability for the given `GameType`
    /// `collection_name` - name of the collection
    /// `token_description` - description of the token
    /// `token_name` - name of the token
    /// `royalty` - royalty of the token
    /// `uri` - uri of the token
    /// `soulbound` - whether the token is soulbound
    public fun mint_token_player<GameType>(
        player_cap: &PlayerCapability<GameType>,
        collection_name: String,
        token_description: String,
        token_name: String,
        royalty: Option<Royalty>,
        uri: String,
        soulbound: bool
    ): ConstructorRef acquires GameAdmin {
        let game_account_signer = get_game_account_signer_player(player_cap);
        let constructor_ref = token::create_from_account(
            &game_account_signer,
            collection_name,
            token_description,
            token_name,
            royalty,
            uri
        );

        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, get_player_address(player_cap));
        if(soulbound) {
            object::disable_ungated_transfer(&transfer_ref);
        };

        constructor_ref
    }

    // access control

    /// creates a game admin capability for the given `GameType`
    /// `game_admin` - must be the deployer of the `GameType` struct
    /// `witness` - ensures that the `GameType` struct is the same as the one that was deployed
    public fun create_game_admin_capability<GameType: drop>(game_admin: &signer, _witness: GameType): GameAdminCapability<GameType> {
        assert_game_admin_initialized<GameType>();
        assert_signer_is_game_admin<GameType>(game_admin);
        GameAdminCapability<GameType> {}
    }

    /// creates a player capability for the given `GameType`
    /// `player` - must be the player of the `GameType` struct
    /// `witness` - ensures that the `GameType` struct is the same as the one that was deployed
    public fun create_player_capability<GameType: drop>(player: &signer, _witness: GameType): PlayerCapability<GameType> {
        assert_game_admin_initialized<GameType>();
        PlayerCapability<GameType> {
            player_address: signer::address_of(player)
        }
    }

    /// gets the address of the player who created the given `PlayerCapability`
    /// `player_cap` - the PlayerCapability
    public fun get_player_address<GameType>(player_cap: &PlayerCapability<GameType>): address {
        player_cap.player_address
    }

    // signer helpers

    /// returns the signer of the game admin resource account for the given `GameType`
    /// `game_admin_cap` - must be a game admin capability for the given `GameType`
    fun get_game_account_signer_admin<GameType>(_admin_cap: &GameAdminCapability<GameType>): signer acquires GameAdmin {
        let game_admin_address = type_info::account_address(&type_info::type_of<GameType>());
        let game_admin = borrow_global<GameAdmin<GameType>>(game_admin_address);
        account::create_signer_with_capability(&game_admin.signer_cap)
    }

    /// returns the signer of the player resource account for the given `GameType`
    /// `player_cap` - must be a player capability for the given `GameType`
    fun get_game_account_signer_player<GameType>(_player_cap: &PlayerCapability<GameType>): signer acquires GameAdmin {
        let game_admin_address = type_info::account_address(&type_info::type_of<GameType>());
        let game_admin = borrow_global<GameAdmin<GameType>>(game_admin_address);
        account::create_signer_with_capability(&game_admin.signer_cap)
    }

    #[view]
    /// returns the address of the game account for the given `GameType`
    public fun get_game_account_address<GameType>(): address {
        account::create_resource_address(
            &type_info::account_address(&type_info::type_of<GameType>()),
            get_game_account_seed<GameType>()
        )
    }

    // helper functions

    /// returns the account address for `GameType`
    fun get_account_address<GameType>(): address {
        type_info::account_address(&type_info::type_of<GameType>())
    }

    /// returns the seed for the game account for the given `GameType`
    fun get_game_account_seed<GameType>(): vector<u8> {
        let account_seed = type_info::struct_name(&type_info::type_of<GameType>());
        vector::append(&mut account_seed, ACCOUNT_SEED_TEMPLATE);
        account_seed
    }

    // assert statements

    /// asserts that the given `signer` is the game admin for the given `GameType`
    /// `game_admin` - must be the deployer of the `GameType` struct
    fun assert_signer_is_game_admin<GameType>(game_admin: &signer) {
        assert!(signer::address_of(game_admin) == type_info::account_address(&type_info::type_of<GameType>()), ESIGNER_NOT_ADMIN);
    }

    /// asserts that the game admin resource account has not been initialized
    fun assert_game_admin_not_initialized<GameType>() {
        assert!(!exists<GameAdmin<GameType>>(get_account_address<GameType>()),EGAME_ACCOUNT_ALREADY_INITIALIZED);
    }

    /// asserts that the game admin resource account has been initialized
    fun assert_game_admin_initialized<GameType>() {
        assert!(exists<GameAdmin<GameType>>(get_account_address<GameType>()),EGAME_ACCOUNT_NOT_INITIALIZED);
    }

    // tests

    #[test_only]
    use std::string;
    #[test_only]
    use std::option;
    #[test_only]
    use aptos_token_objects::collection::Collection;
    #[test_only]
    use aptos_token_objects::token::Token;

    #[test_only]
    struct TestGame has drop {}

    #[test(aptos_arcade=@aptos_arcade)]
    fun test_initialize(aptos_arcade: &signer) {
        assert_game_admin_not_initialized<TestGame>();
        initialize<TestGame>(aptos_arcade, TestGame {});
        assert_game_admin_initialized<TestGame>();
    }

    #[test(not_aptos_arcade=@0x100)]
    #[expected_failure(abort_code=ESIGNER_NOT_ADMIN)]
    fun test_initialize_unauthorized(not_aptos_arcade: &signer) {
        initialize<TestGame>(not_aptos_arcade, TestGame {});
    }

    #[test(aptos_arcade=@aptos_arcade)]
    #[expected_failure(abort_code=EGAME_ACCOUNT_ALREADY_INITIALIZED)]
    fun test_initialize_twice(aptos_arcade: &signer) {
        initialize<TestGame>(aptos_arcade, TestGame {});
        initialize<TestGame>(aptos_arcade, TestGame {});
    }

    #[test(aptos_arcade=@aptos_arcade)]
    fun test_create_game_admin_cap(aptos_arcade: &signer) acquires GameAdmin {
        initialize<TestGame>(aptos_arcade, TestGame {});
        let admin_cap = create_game_admin_capability<TestGame>(aptos_arcade, TestGame {});
        let admin_signer = get_game_account_signer_admin(&admin_cap);
        assert!(signer::address_of(&admin_signer) == get_game_account_address<TestGame>(), 0);
    }

    #[test(aptos_arcade=@aptos_arcade, not_aptos_arcade=@0x100)]
    #[expected_failure(abort_code=ESIGNER_NOT_ADMIN)]
    fun test_create_game_admin_cap_unauthorized(aptos_arcade: &signer, not_aptos_arcade: &signer) {
        initialize<TestGame>(aptos_arcade, TestGame {});
        create_game_admin_capability<TestGame>(not_aptos_arcade, TestGame {});
    }

    #[test(aptos_arcade=@aptos_arcade)]
    #[expected_failure(abort_code=EGAME_ACCOUNT_NOT_INITIALIZED)]
    fun test_create_game_admin_cap_uninitialized(aptos_arcade: &signer) {
        create_game_admin_capability<TestGame>(aptos_arcade, TestGame {});
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    fun test_create_player_cap(aptos_arcade: &signer, player: &signer) acquires GameAdmin {
        initialize<TestGame>(aptos_arcade, TestGame {});
        let admin_cap = create_player_capability<TestGame>(player, TestGame {});
        let admin_signer = get_game_account_signer_player(&admin_cap);
        assert!(signer::address_of(&admin_signer) == get_game_account_address<TestGame>(), 0);
    }

    #[test(player=@0x100)]
    #[expected_failure(abort_code=EGAME_ACCOUNT_NOT_INITIALIZED)]
    fun test_create_player_cap_uninitialized(player: &signer) {
        create_player_capability<TestGame>(player, TestGame {});
    }


    #[test(aptos_arcade=@aptos_arcade)]
    fun test_create_collection(aptos_arcade: &signer) acquires GameAdmin {
        initialize<TestGame>(aptos_arcade, TestGame {});
        let admin_cap = create_game_admin_capability<TestGame>(aptos_arcade, TestGame {});
        let collection_name = string::utf8(b"test_collection");
        let collection_description = string::utf8(b"test_description");
        let collection_uri = string::utf8(b"test_uri");
        let collection_royalty = option::none<Royalty>();
        let constructor_ref = create_collection(
            &admin_cap,
            collection_description,
            collection_name,
            collection_royalty,
            collection_uri,
        );
        let collection_object = object::object_from_constructor_ref<Collection>(&constructor_ref);
        assert!(collection::creator(collection_object) == get_game_account_address<TestGame>(), 0);
        assert!(collection::name(collection_object) == collection_name, 0);
        assert!(collection::description(collection_object) == collection_description, 0);
        assert!(collection::uri(collection_object) == collection_uri, 0);
    }

    #[test(aptos_arcade=@aptos_arcade)]
    fun test_mint_token_admin(aptos_arcade: &signer) acquires GameAdmin {
        initialize<TestGame>(aptos_arcade, TestGame {});
        let admin_cap = create_game_admin_capability<TestGame>(aptos_arcade, TestGame {});

        let collection_name = string::utf8(b"test_collection");
        let collection_description = string::utf8(b"test_description");
        let collection_uri = string::utf8(b"test_uri");
        let collection_royalty = option::none<Royalty>();
        create_collection(
            &admin_cap,
            collection_description,
            collection_name,
            collection_royalty,
            collection_uri,
        );

        let token_name = string::utf8(b"test_token");
        let token_description = string::utf8(b"test_description");
        let token_uri = string::utf8(b"test_uri");
        let token_royalty = option::none<Royalty>();
        let token_constructor_ref = mint_token_game_admin(
            &admin_cap,
            collection_name,
            token_description,
            token_name,
            token_royalty,
            token_uri
        );
        let token_object = object::object_from_constructor_ref<Token>(&token_constructor_ref);
        assert!(token::creator(token_object) == get_game_account_address<TestGame>(), 0);
        assert!(token::name(token_object) == token_name, 0);
        assert!(token::description(token_object) == token_description, 0);
        assert!(token::uri(token_object) == token_uri, 0);
        assert!(object::is_owner(token_object, get_game_account_address<TestGame>()), 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    fun test_mint_token_transferrable_player(aptos_arcade: &signer, player: &signer) acquires GameAdmin {
        initialize<TestGame>(aptos_arcade, TestGame {});
        let admin_cap = create_game_admin_capability<TestGame>(aptos_arcade, TestGame {});

        let collection_name = string::utf8(b"test_collection");
        let collection_description = string::utf8(b"test_description");
        let collection_uri = string::utf8(b"test_uri");
        let collection_royalty = option::none<Royalty>();
        create_collection(
            &admin_cap,
            collection_description,
            collection_name,
            collection_royalty,
            collection_uri,
        );

        let player_cap = create_player_capability<TestGame>(player, TestGame {});
        let token_name = string::utf8(b"test_token");
        let token_description = string::utf8(b"test_description");
        let token_uri = string::utf8(b"test_uri");
        let token_royalty = option::none<Royalty>();
        let token_constructor_ref = mint_token_player(
            &player_cap,
            collection_name,
            token_description,
            token_name,
            token_royalty,
            token_uri,
            false
        );
        let token_object = object::object_from_constructor_ref<Token>(&token_constructor_ref);
        assert!(token::creator(token_object) == get_game_account_address<TestGame>(), 0);
        assert!(token::name(token_object) == token_name, 0);
        assert!(token::description(token_object) == token_description, 0);
        assert!(token::uri(token_object) == token_uri, 0);
        assert!(object::is_owner(token_object, signer::address_of(player)), 0);
        object::transfer(player, token_object, get_game_account_address<TestGame>());
        assert!(object::is_owner(token_object, get_game_account_address<TestGame>()), 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    fun test_mint_token_nontransferrable_player(aptos_arcade: &signer, player: &signer) acquires GameAdmin {
        initialize<TestGame>(aptos_arcade, TestGame {});
        let admin_cap = create_game_admin_capability<TestGame>(aptos_arcade, TestGame {});

        let collection_name = string::utf8(b"test_collection");
        let collection_description = string::utf8(b"test_description");
        let collection_uri = string::utf8(b"test_uri");
        let collection_royalty = option::none<Royalty>();
        create_collection(
            &admin_cap,
            collection_description,
            collection_name,
            collection_royalty,
            collection_uri,
        );

        let player_cap = create_player_capability<TestGame>(player, TestGame {});
        let token_name = string::utf8(b"test_token");
        let token_description = string::utf8(b"test_description");
        let token_uri = string::utf8(b"test_uri");
        let token_royalty = option::none<Royalty>();
        let token_constructor_ref = mint_token_player(
            &player_cap,
            collection_name,
            token_description,
            token_name,
            token_royalty,
            token_uri,
            true
        );
        let token_object = object::object_from_constructor_ref<Token>(&token_constructor_ref);
        assert!(token::creator(token_object) == get_game_account_address<TestGame>(), 0);
        assert!(token::name(token_object) == token_name, 0);
        assert!(token::description(token_object) == token_description, 0);
        assert!(token::uri(token_object) == token_uri, 0);
        assert!(object::is_owner(token_object, signer::address_of(player)), 0);
        assert!(!object::ungated_transfer_allowed(token_object), 0);
    }



}
