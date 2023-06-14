module aptos_arcade::scripts {

    use aptos_framework::object::Object;

    use aptos_arcade::game_admin::{Self, GameAdminCapability};
    use aptos_arcade::elo;
    use aptos_arcade::match::{Self, Match};

    /// initializes the Aptos Arcade modules for a specific game
    /// `game_admin` - must be the deployer of the GameType struct
    /// `witness` - an instance of the GameType struct
    public fun initialize<GameType: drop>(game_admin: &signer, witness: GameType): GameAdminCapability<GameType> {
        let game_admin_cap = game_admin::initialize(game_admin, witness);
        elo::initialize_elo_collection(&game_admin_cap);
        match::initialize_matches_collection(&game_admin_cap);
        game_admin_cap
    }

    /// mints an ELO token for a player
    /// `player` - each player can mint only one ELO token per game
    /// `witness` - ann instance of the GameType struct
    public fun mint_elo_token<GameType: drop>(player: &signer, witness: GameType) {
        elo::mint_elo_token(&game_admin::create_player_capability(player, witness));
    }

    /// creates a match between a set of teams
    /// `game_admin` - must be the deployer of the GameType struct
    /// `witness` - an instance of the GameType struct
    /// `teams` - a vector of teams, each team is a vector of player addresses
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

    /// sets the result of a match
    /// `game_admin` - must be the deployer of the GameType struct
    /// `witness` - an instance of the GameType struct
    /// `match` - the match object
    /// `winner_index` - the index of the winning team
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
