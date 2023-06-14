module aptos_arcade::elo {

    use std::string::{Self, String};
    use std::option;
    use std::vector;

    use aptos_std::type_info;
    use aptos_std::string_utils;

    use aptos_framework::object;

    use aptos_arcade::game_admin::{Self, GameAdminCapability, PlayerCapability};

    friend aptos_arcade::match;

    // error codes

    /// when a player has already minted an EloRating for a `GameType`
    const EPLAYER_HAS_MINTED: u64 = 0;

    /// when a player has not minted an EloRating for a `GameType`
    const EPLAYER_HAS_NOT_MINTED: u64 = 1;

    // constants

    const COLLECTION_BASE_NAME: vector<u8> = b"{} ELO Ratings";
    const COLLECTION_BASE_DESCRIPTION: vector<u8> = b"On-chain ELO rating system for {}.";
    const COLLECTION_URI: vector<u8> = b"aptos://elo";

    const TOKEN_BASE_NAME: vector<u8> =  b"{} ELO Rating";
    const TOKEN_BASE_DESCRIPTION: vector<u8> = b"On-chain ELO rating for {}.";
    const TOKEN_BASE_URI: vector<u8> = b"aptos://elo";

    const INITIAL_ELO_RATING: u64 = 100;
    const ELO_RATING_CHANGE: u64 = 5;

    // structs

    struct EloRating<phantom GameType> has key {
        rating: u64,
        wins: u64,
        losses: u64
    }

    // public functions

    /// initializes an ELO collection for a game
    /// `game_signer` - must be the account that created `game_struct`
    public fun initialize_elo_collection<GameType: drop>(game_admin_cap: &GameAdminCapability<GameType>) {
        // create an ELO collection under the game admin signer
        game_admin::create_one_to_one_collection(
            game_admin_cap,
            get_collection_description<GameType>(),
            get_collection_name<GameType>(),
            option::none(),
            string::utf8(COLLECTION_URI),
        );
    }

    /// mints an ELO token for a player for `GameType`
    /// `player` - can only mint one ELO token per game
    public fun mint_elo_token<GameType: drop>(player_cap: &PlayerCapability<GameType>) {
        // assert collection has been initialized and player has not minted
        assert_player_has_not_minted<GameType>(game_admin::get_player_address(player_cap));

        // mint ELO token
        let constructor_ref = game_admin::mint_token_player(
            player_cap,
            get_collection_name<GameType>(),
            get_token_description<GameType>(),
            get_token_name<GameType>(),
            option::none(),
            get_token_uri<GameType>(),
            true
        );

        // add ELO rating resource
        let token_signer = object::generate_signer(&constructor_ref);
        move_to(&token_signer, EloRating<GameType> {
            rating: INITIAL_ELO_RATING,
            wins: 0,
            losses: 0
        });
    }

    /// updates the ELO ratings for a set of teams
    /// `teams` - a vector of vectors of player addresses
    /// `winner_index` - the index of the winning team
    public(friend) fun update_match_elo_ratings<GameType>(teams: vector<vector<address>>, winner_index: u64)
    acquires EloRating {
        vector::enumerate_ref(&teams, |index, team| {
            update_team_elo_ratings<GameType>(*team, index == winner_index);
        });
    }

    /// updates the ELO ratings for a team given the outcome of a match
    /// `team` - a vector of player addresses
    /// `win` - true if the team won, false if the team lost
    fun update_team_elo_ratings<GameType>(
        team: vector<address>,
        win: bool
    ) acquires EloRating {
        vector::for_each(team, |player_address| update_player_elo_rating<GameType>(player_address, win));
    }

    /// updates the ELO rating for a player given the outcome of a match
    /// `elo_rating_object` - the ELO rating object for the player
    /// `win` - true if the player won, false if the player lost
    fun update_player_elo_rating<GameType>(player_address: address, win: bool) acquires EloRating {
        assert_player_has_minted<GameType>(player_address);
        let elo_rating_address = get_player_elo_object_address<GameType>(player_address);
        let elo_rating_object = object::address_to_object<EloRating<GameType>>(elo_rating_address);
        let elo_rating = borrow_global_mut<EloRating<GameType>>(object::object_address(&elo_rating_object));
        if(win) {
            elo_rating.wins = elo_rating.wins + 1;
        } else {
            elo_rating.losses = elo_rating.losses + 1;
        };
        elo_rating.rating = if(win) {
            elo_rating.rating + ELO_RATING_CHANGE
        } else {
            if(elo_rating.rating > ELO_RATING_CHANGE) {
                elo_rating.rating - ELO_RATING_CHANGE
            } else {
                0
            }
        };
    }

    // helper functions

    fun get_collection_name<GameType>(): String {
        string_utils::format1(&COLLECTION_BASE_NAME, type_info::struct_name(&type_info::type_of<GameType>()))
    }

    fun get_collection_description<GameType>(): String {
        string_utils::format1(&COLLECTION_BASE_DESCRIPTION, type_info::struct_name(&type_info::type_of<GameType>()))
    }

    fun get_collection_uri(): String {
        string::utf8(COLLECTION_URI)
    }

    fun get_token_name<GameType>(): String {
        string_utils::format1(&TOKEN_BASE_NAME, type_info::struct_name(&type_info::type_of<GameType>()))
    }

    fun get_token_description<GameType>(): String {
        string_utils::format1(&TOKEN_BASE_DESCRIPTION,type_info::struct_name(&type_info::type_of<GameType>()))
    }

    fun get_token_uri<GameType>(): String {
        string::utf8(TOKEN_BASE_URI)
    }

    // view functions

    #[view]
    /// gets the address of the ELO collection object for `GameType`
    public fun get_elo_collection_address<GameType>(): address {
        game_admin::get_collection_address<GameType>(get_collection_name<GameType>())
    }

    #[view]
    /// gets the address of the ELO rating token for `player` in `GameType`
    /// `player_address` - the player whose ELO rating token address to get
    public fun get_player_elo_object_address<GameType>(player_address: address): address {
        game_admin::get_player_token_address<GameType>(get_collection_name<GameType>(), player_address)
    }

    #[view]
    /// gets the ELO rating for `player` in `GameType`
    /// `player_address` - the player whose ELO rating to get
    public fun get_player_elo_rating<GameType>(player_address: address): (u64, u64, u64) acquires EloRating {
        let elo_rating_address = get_player_elo_object_address<GameType>(player_address);
        let elo_rating_object = object::address_to_object<EloRating<GameType>>(elo_rating_address);
        let elo_rating = borrow_global<EloRating<GameType>>(object::object_address(&elo_rating_object));
        (elo_rating.rating, elo_rating.wins, elo_rating.losses)
    }

    #[view]
    /// gets whether or not a player has minted an ELO rating token for `GameType`
    /// `player_address` - the player address
    public fun has_player_minted<GameType>(player_address: address): bool {
        game_admin::has_player_received_token<GameType>(get_collection_name<GameType>(), player_address)
    }

    // assert statements

    /// asserts that a player has not minted an ELO token for `GameType`
    /// `player_address` - the player address
    fun assert_player_has_not_minted<GameType>(player_address: address) {
        assert!(!has_player_minted<GameType>(player_address),EPLAYER_HAS_MINTED);
    }

    /// asserts that a player has minted an ELO token for `GameType`
    /// `player_address` - the player address
    fun assert_player_has_minted<GameType>(player_address: address) {
        assert!(has_player_minted<GameType>(player_address), EPLAYER_HAS_NOT_MINTED);
    }

    // tests

    #[test_only]
    struct TestGame has drop {}

    #[test_only]
    use std::signer;
    #[test_only]
    use aptos_token_objects::token;
    #[test_only]
    use aptos_token_objects::collection;
    #[test_only]
    use aptos_arcade::game_admin::Collection;

    #[test(aptos_arcade=@aptos_arcade)]
    fun test_initialize_elo_collection(aptos_arcade: &signer) {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        let collection_object = object::address_to_object<Collection<TestGame>>(
            get_elo_collection_address<TestGame>()
        );
        assert!(collection::name(collection_object) == get_collection_name<TestGame>(), 0);
        assert!(collection::description(collection_object) == get_collection_description<TestGame>(), 0);
        assert!(collection::uri(collection_object) == get_collection_uri(), 0);
        assert!(*option::borrow(&collection::count(collection_object)) == 0, 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    fun test_mint_token(aptos_arcade: &signer, player: &signer) acquires EloRating {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        mint_elo_token(&game_admin::create_player_capability(player, TestGame {}));

        let player_address = signer::address_of(player);
        assert_player_has_minted<TestGame>(player_address);

        let token_object = object::address_to_object<EloRating<TestGame>>(
            get_player_elo_object_address<TestGame>(player_address)
        );
        assert!(token::name(token_object) == get_token_name<TestGame>(), 0);
        assert!(token::description(token_object) == get_token_description<TestGame>(), 0);
        assert!(token::uri(token_object) == get_token_uri<TestGame>(), 0);
        assert!(object::is_owner(token_object, player_address), 0);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player_address);
        assert!(rating == INITIAL_ELO_RATING, 0);
        assert!(wins == 0, 0);
        assert!(losses == 0, 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    #[expected_failure(abort_code=EPLAYER_HAS_MINTED)]
    fun test_mint_token_twice(aptos_arcade: &signer, player: &signer) {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        mint_elo_token(&game_admin::create_player_capability(player, TestGame {}));
        mint_elo_token(&game_admin::create_player_capability(player, TestGame {}));
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    fun test_update_player_elo_rating(aptos_arcade: &signer, player: &signer) acquires EloRating {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        mint_elo_token(&game_admin::create_player_capability(player, TestGame {}));

        let player_address = signer::address_of(player);

        update_player_elo_rating<TestGame>(player_address, true);
        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player_address);
        assert!(rating == INITIAL_ELO_RATING + ELO_RATING_CHANGE, 0);
        assert!(wins == 1, 0);
        assert!(losses == 0, 0);

        update_player_elo_rating<TestGame>(player_address, false);
        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player_address);
        assert!(rating == INITIAL_ELO_RATING, 0);
        assert!(wins == 1, 0);
        assert!(losses == 1, 0);

        let i = 0;
        let iterations = INITIAL_ELO_RATING / ELO_RATING_CHANGE + 1;
        while (i < iterations)
        {
            update_player_elo_rating<TestGame>(player_address, false);
            i = i + 1;
        };
        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player_address);
        assert!(rating == 0, 0);
        assert!(wins == 1, 0);
        assert!(losses == iterations + 1, 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player=@0x100)]
    #[expected_failure(abort_code=EPLAYER_HAS_NOT_MINTED)]
    fun test_update_player_elo_rating_before_mint(aptos_arcade: &signer, player: &signer)
    acquires EloRating {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        update_player_elo_rating<TestGame>(signer::address_of(player), true);
    }

    #[test(aptos_arcade=@aptos_arcade, player1=@0x100, player2=@0x101)]
    fun test_update_team_elo_rating(aptos_arcade: &signer, player1: &signer, player2: &signer) acquires EloRating {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        mint_elo_token(&game_admin::create_player_capability(player1, TestGame {}));
        mint_elo_token(&game_admin::create_player_capability(player2, TestGame {}));
        let team = vector<address>[signer::address_of(player1), signer::address_of(player2)];

        update_team_elo_ratings<TestGame>(team, true);

        let player1_address = signer::address_of(player1);
        let player2_address = signer::address_of(player2);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player1_address);
        assert!(rating == INITIAL_ELO_RATING + ELO_RATING_CHANGE, 0);
        assert!(wins == 1, 0);
        assert!(losses == 0, 0);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player2_address);
        assert!(rating == INITIAL_ELO_RATING + ELO_RATING_CHANGE, 0);
        assert!(wins == 1, 0);
        assert!(losses == 0, 0);

        update_team_elo_ratings<TestGame>(team, false);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player1_address);
        assert!(rating == INITIAL_ELO_RATING, 0);
        assert!(wins == 1, 0);
        assert!(losses == 1, 0);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player2_address);
        assert!(rating == INITIAL_ELO_RATING, 0);
        assert!(wins == 1, 0);
        assert!(losses == 1, 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player1=@0x100, player2=@0x101)]
    #[expected_failure(abort_code=EPLAYER_HAS_NOT_MINTED)]
    fun test_update_team_elo_rating_before_mint(aptos_arcade: &signer, player1: &signer, player2: &signer)
    acquires EloRating {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        mint_elo_token(&game_admin::create_player_capability(player1, TestGame {}));
        let team = vector<address>[signer::address_of(player1), signer::address_of(player2)];
        update_team_elo_ratings<TestGame>(team, true);
    }

    #[test(aptos_arcade=@aptos_arcade, player1=@0x100, player2=@0x101, player3=@0x102, player4=@0x103)]
    fun test_update_match_elo_rating(
        aptos_arcade: &signer,
        player1: &signer,
        player2: &signer,
        player3: &signer,
        player4: &signer
    ) acquires EloRating {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        mint_elo_token(&game_admin::create_player_capability(player1, TestGame {}));
        mint_elo_token(&game_admin::create_player_capability(player2, TestGame {}));
        mint_elo_token(&game_admin::create_player_capability(player3, TestGame {}));
        mint_elo_token(&game_admin::create_player_capability(player4, TestGame {}));
        let team1 = vector<address>[signer::address_of(player1), signer::address_of(player2)];
        let team2 = vector<address>[signer::address_of(player3), signer::address_of(player4)];
        let teams = vector<vector<address>>[team1, team2];
        update_match_elo_ratings<TestGame>(teams, 0);

        let player1_address = signer::address_of(player1);
        let player2_address = signer::address_of(player2);
        let player3_address = signer::address_of(player3);
        let player4_address = signer::address_of(player4);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player1_address);
        assert!(rating == INITIAL_ELO_RATING + ELO_RATING_CHANGE, 0);
        assert!(wins == 1, 0);
        assert!(losses == 0, 0);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player2_address);
        assert!(rating == INITIAL_ELO_RATING + ELO_RATING_CHANGE, 0);
        assert!(wins == 1, 0);
        assert!(losses == 0, 0);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player3_address);
        assert!(rating == INITIAL_ELO_RATING - ELO_RATING_CHANGE, 0);
        assert!(wins == 0, 0);
        assert!(losses == 1, 0);

        let (rating, wins, losses) = get_player_elo_rating<TestGame>(player4_address);
        assert!(rating == INITIAL_ELO_RATING - ELO_RATING_CHANGE, 0);
        assert!(wins == 0, 0);
        assert!(losses == 1, 0);
    }

    #[test(aptos_arcade=@aptos_arcade, player1=@0x100, player2=@0x101, player3=@0x102, player4=@0x103)]
    #[expected_failure(abort_code=EPLAYER_HAS_NOT_MINTED)]
    fun test_update_match_elo_rating_before_mint(
        aptos_arcade: &signer,
        player1: &signer,
        player2: &signer,
        player3: &signer,
        player4: &signer
    ) acquires EloRating {
        let game_admin_cap = game_admin::initialize(aptos_arcade, TestGame {});
        initialize_elo_collection(&game_admin_cap);
        mint_elo_token(&game_admin::create_player_capability(player1, TestGame {}));
        mint_elo_token(&game_admin::create_player_capability(player2, TestGame {}));
        mint_elo_token(&game_admin::create_player_capability(player3, TestGame {}));

        let team1 = vector<address>[signer::address_of(player1), signer::address_of(player2)];
        let team2 = vector<address>[signer::address_of(player3), signer::address_of(player4)];
        let teams = vector<vector<address>>[team1, team2];
        update_match_elo_ratings<TestGame>(teams, 0);
    }

}
