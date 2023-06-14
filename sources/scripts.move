module aptos_arcade::scripts {

    use aptos_arcade::game_admin;
    use aptos_arcade::elo;
    use aptos_arcade::match;
    use aptos_framework::object::Object;
    use aptos_arcade::match::Match;

    public fun initialize<GameType: drop>(game_admin: &signer, witness: GameType): GameAdminCapability<GameType> {
        let game_admin_cap = game_admin::initialize(game_admin, witness);
        elo::initialize_elo_collection(&game_admin_cap);
        match::initialize_matches_collection(&game_admin_cap);
        game_admin_cap
    }

    public fun mint_elo_token<GameType: drop>(player: &signer, witness: GameType) {
        elo::mint_elo_token(&game_admin::create_player_capability(player, witness));
    }

    public fun create_match<GameType: drop>(
        game_admin: &signer,
        witness: GameType,
        teams: vector<vector<address>>
    ): Object<Match<GameType>> {
        match::create_match(
            &game_admin::create_game_admin_capability(game_admin, witness),
            teams,
        )
    }

    public fun set_match_result<GameType: drop>(
        game_admin: &signer,
        witness: GameType,
        match: Object<Match<GameType>>,
        winner_index: u64
    ) {
        match::set_match_result(
            &game_admin::create_game_admin_capability(game_admin, witness),
            match,
            winner_index
        );
    }

    // tests

    #[test_only]
    use std::signer;
    use aptos_arcade::game_admin::GameAdminCapability;

    #[test_only]
    struct TestGame has drop {}

    #[test(aptos_arcade=@aptos_arcade, player1=@0x100, player2=@0x101)]
    fun test_e2e(aptos_arcade: &signer, player1: &signer, player2: &signer) {
        aptos_arcade::scripts::initialize(aptos_arcade, TestGame {});
        aptos_arcade::scripts::mint_elo_token(player1, TestGame {});
        aptos_arcade::scripts::mint_elo_token(player2, TestGame {});
        let match_object = aptos_arcade::scripts::create_match(
            aptos_arcade,
            TestGame {},
            vector<vector<address>>[
                vector<address>[signer::address_of(player1)],
                vector<address>[signer::address_of(player2)]
            ]
        );
        aptos_arcade::scripts::set_match_result(
            aptos_arcade,
            TestGame {},
            match_object,
            0
        );
    }
}
