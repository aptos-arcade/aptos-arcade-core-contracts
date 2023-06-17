module aptos_arcade::stats {

    use std::option;
    use std::string::String;

    use aptos_std::string_utils;
    use aptos_std::type_info;

    use aptos_framework::object;

    use aptos_arcade::game_admin::{Self, GameAdminCapability, PlayerCapability};
    use aptos_framework::object::ConstructorRef;

    // constants

    const BASE_COLLECTION_NAME: vector<u8> = b"{}: {}";
    const BASE_COLLECTION_DESCRIPTION: vector<u8> = b"{} stat for {}";
    const BASE_COLLECTION_URI: vector<u8> = b"https://aptosarcade.com/api/stats/{}/{}";

    const BASE_TOKEN_NAME: vector<u8> = b"{} {}: {}";
    const BASE_TOKEN_DESCRIPTION: vector<u8> = b"{}'s {} stat for {}";
    const BASE_TOKEN_URI: vector<u8> = b"https://aptosarcade.com/api/stats/{}/{}/{}";

    // structs

    /// a Stat is that is tracked in a GameType
    struct Stat<phantom GameType, phantom StatType> has key {
        value: u64
    }

    /// creates a new StatType collection for a GameType
    /// `game_admin_cap` - the game admin capability
    /// `witness` - a witness of the StatType
    public fun create_stat<GameType: drop, StatType: drop>(
        game_admin_cap: &GameAdminCapability<GameType>,
        _witness: StatType,
    ): ConstructorRef {
        game_admin::create_collection(
            game_admin_cap,
            get_stat_collection_description<GameType, StatType>(),
            get_stat_collection_name<GameType, StatType>(),
            option::none(),
            get_stat_collection_uri<GameType, StatType>(),
            true,
            true,
            true,
        )
    }

    /// mints a new StatType token for a player in a GameType
    /// `player_cap` - the player capability
    /// `default_value` - the default value of the stat
    /// `witness` - a witness of the StatType
    public fun mint_stat<GameType: drop, StatType: drop>(
        player_cap: &PlayerCapability<GameType>,
        default_value: u64,
        _witness: StatType,
    ): ConstructorRef {
        let player_address = game_admin::get_player_address(player_cap);
        let constructor_ref = game_admin::mint_token_player(
            player_cap,
            get_stat_collection_name<GameType, StatType>(),
            get_stat_token_description<GameType, StatType>(player_address),
            get_stat_token_name<GameType, StatType>(player_address),
            option::none(),
            get_stat_token_uri<GameType, StatType>(player_address)
        );

        move_to(&object::generate_signer(&constructor_ref), Stat<GameType, StatType> {
            value: default_value
        });

        constructor_ref
    }

    /// updates the value of a StatType token for a player in a GameType
    /// `game_admin_cap` - the game admin capability
    /// `player_address` - the address of the player
    /// `new_amount` - the new amount of the stat
    /// `witness` - a witness of the StatType
    public fun update_stat<GameType: drop, StatType: drop>(
        _game_admin_cap: &GameAdminCapability<GameType>,
        player_address: address,
        new_amount: u64,
        _witness: StatType,
    ) acquires Stat {
        let stat_token_address = get_player_stat_token_address<GameType, StatType>(player_address);
        let stat = borrow_global_mut<Stat<GameType, StatType>>(stat_token_address);
        stat.value = new_amount;
    }

    // view functions

    #[view]
    /// gets whether a stat collection exists
    public fun stat_collection_exists<GameType, StatType>(): bool {
        game_admin::does_collection_exist<GameType>(get_stat_collection_name<GameType, StatType>())
    }

    #[view]
    /// gets the StatType collection address for a GameType
    public fun get_stat_collection_address<GameType, StatType>(): address {
        game_admin::get_collection_address<GameType>(get_stat_collection_name<GameType, StatType>())
    }

    #[view]
    /// gets the StatType token address for a player in a GameType
    public fun get_player_stat_token_address<GameType, StatType>(player: address): address {
        game_admin::get_player_token_address<GameType>(
            get_stat_collection_name<GameType, StatType>(),
            player,
        )
    }

    #[view]
    /// gets the value of a StatType token for a player in a GameType
    public fun get_player_stat_value<GameType, StatType>(player: address): u64 acquires Stat {
        let token_address = get_player_stat_token_address<GameType, StatType>(player);
        let stat = borrow_global<Stat<GameType, StatType>>(token_address);
        stat.value
    }


    // string constructors

    /// gets the StatType collection name for a GameType
    fun get_stat_collection_name<GameType, StatType>(): String {
        string_utils::format2(
            &BASE_COLLECTION_NAME,
            type_info::struct_name(&type_info::type_of<GameType>()),
            type_info::struct_name(&type_info::type_of<StatType>())
        )
    }

    /// gets the StatType token name for a player in a GameType
    fun get_stat_collection_description<GameType, StatType>(): String {
        string_utils::format2(
            &BASE_COLLECTION_DESCRIPTION,
            type_info::struct_name(&type_info::type_of<StatType>()),
            type_info::struct_name(&type_info::type_of<GameType>())
        )
    }

    /// gets the StatType collection URI for a GameType
    fun get_stat_collection_uri<GameType, StatType>(): String {
        string_utils::format2(
            &BASE_COLLECTION_URI,
            type_info::struct_name(&type_info::type_of<GameType>()),
            type_info::struct_name(&type_info::type_of<StatType>())
        )
    }

    /// gets the StatType token URI for a player in a GameType
    fun get_stat_token_name<GameType, StatType>(player: address): String {
        string_utils::format3(
            &BASE_TOKEN_NAME,
            type_info::struct_name(&type_info::type_of<GameType>()),
            type_info::struct_name(&type_info::type_of<StatType>()),
            player
        )
    }

    /// gets the StatType token description for a player in a GameType
    fun get_stat_token_description<GameType, StatType>(player: address): String {
        string_utils::format3(
            &BASE_TOKEN_DESCRIPTION,
            player,
            type_info::struct_name(&type_info::type_of<StatType>()),
            type_info::struct_name(&type_info::type_of<GameType>())
        )
    }

    /// gets the StatType token URI for a player in a GameType
    fun get_stat_token_uri<GameType, StatType>(player: address): String {
        string_utils::format3(
            &BASE_TOKEN_URI,
            type_info::struct_name(&type_info::type_of<GameType>()),
            type_info::struct_name(&type_info::type_of<StatType>()),
            player
        )
    }

    // tests

    #[test_only]
    use std::signer;
    #[test_only]
    use aptos_token_objects::collection::{Self, Collection};
    #[test_only]
    use aptos_token_objects::token::{Self, Token};

    #[test_only]
    struct TestGame has drop {}

    #[test_only]
    struct TestStat has drop {}

    #[test(aptos_arcade=@aptos_arcade)]
    fun test_create_stats_collection(aptos_arcade: &signer) {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        let constructor_ref = create_stat(&game_admin_cap, TestStat {});
        let collection_object = object::object_from_constructor_ref<Collection>(&constructor_ref);
        let collection_address = object::address_from_constructor_ref(&constructor_ref);
        assert!(stat_collection_exists<TestGame, TestStat>(), 0);
        assert!(collection::name(collection_object) == get_stat_collection_name<TestGame, TestStat>(), 0);
        assert!(collection::description(collection_object) == get_stat_collection_description<TestGame, TestStat>(), 0);
        assert!(collection::uri(collection_object) == get_stat_collection_uri<TestGame, TestStat>(), 0);
        assert!(collection_address == get_stat_collection_address<TestGame, TestStat>(), 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    fun test_mint_stat(aptos_arcade: &signer, player: &signer) acquires Stat {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        create_stat(&game_admin_cap, TestStat {});
        let default_value = 100;
        let constructor_ref = mint_stat(
            &game_admin::create_player_capability(player, TestGame {}),
            default_value,
            TestStat {}
        );
        let player_address = signer::address_of(player);
        let token_object = object::object_from_constructor_ref<Token>(&constructor_ref);
        let token_address = object::address_from_constructor_ref(&constructor_ref);
        assert!(token::name(token_object) == get_stat_token_name<TestGame, TestStat>(player_address), 0);
        assert!(token::description(token_object) == get_stat_token_description<TestGame, TestStat>(player_address), 0);
        assert!(token::uri(token_object) == get_stat_token_uri<TestGame, TestStat>(player_address), 0);
        assert!(object::is_owner(token_object, player_address), 0);
        assert!(token_address == get_player_stat_token_address<TestGame, TestStat>(player_address), 0);
        assert!(get_player_stat_value<TestGame, TestStat>(player_address) == default_value, 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    fun test_update_stat_value(aptos_arcade: &signer, player: &signer) acquires Stat {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        create_stat(&game_admin_cap, TestStat {});
        let default_value = 100;
        mint_stat(
            &game_admin::create_player_capability(player, TestGame {}),
            default_value,
            TestStat {}
        );
        let player_address = signer::address_of(player);
        let new_value = 200;
        update_stat(&game_admin_cap, player_address, new_value, TestStat {});
        assert!(get_player_stat_value<TestGame, TestStat>(player_address) == new_value, 0);
    }
}
