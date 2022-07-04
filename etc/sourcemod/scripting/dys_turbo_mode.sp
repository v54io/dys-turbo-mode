#include <sourcemod>
#include <sdktools>

#pragma newdecls required // git gud
#pragma semicolon 1 // git gud

public Plugin myinfo =
{
	name = "Turbo Mode™",
	author = "SEA.LEVEL.RISES™",
	description = "Reduces respawn timer penalty for games with a large number of players.",
	version = "0.2",
	url = "sealevelrises.net"
}


static bool g_bIsDystopia = false;

#define TEAM_PUNKS 2
#define TEAM_CORPS 3

static int g_iTeams[4] = { -1, -1, -1, -1 };
static int g_iPlayersPlaying = 0;
static int g_iPlayerActivationThreshold = 12; // must exceed this
static bool g_bTurboEnabled = false;
static bool g_bEnableForTesting = false;
static char g_sTurboStatusStrings[][] = {
	"\x04[TURBO MODE DISABLED]\x01 Respawn time penalties have returned to normal.",
	"\x04[TURBO MODE ENABLED]\x01 Spawn times will be reduced based on the number of active players."
};
static int g_iPlayerTeams[MAXPLAYERS+1];


public void OnPluginStart() {
	char game[64];
	GetGameFolderName( game, sizeof(game) );

	if ( !StrEqual( game, "dystopia", false ) )
		return;
	
	g_bIsDystopia = true;
	
	char sPlayerActivationThreshold[64];
	IntToString( g_iPlayerActivationThreshold, sPlayerActivationThreshold, sizeof(sPlayerActivationThreshold) );
	ConVar cvTurboRequiredPlayers = CreateConVar( "turbo_required_players", sPlayerActivationThreshold, "Required number of players to enable turbo mode; must exceed this number.", FCVAR_NOTIFY, true, 0.0, true, float(MaxClients) );
	HookConVarChange( cvTurboRequiredPlayers, ConVar_TurboRequiredPlayers );
	
	HookEvent( "player_death", Event_PlayerDeath, EventHookMode_Post );
	HookEvent( "player_team", Event_PlayerTeam, EventHookMode_Post );
	HookEvent( "round_restart", Event_RoundRestart, EventHookMode_Post );
	
	// RegAdminCmd( "turbo_status", TurboStatus, ADMFLAG_RCON );
	
	// RegAdminCmd( "turbo_team", TurboTeam, ADMFLAG_RCON );
	
}

public void OnMapStart() {
	if ( !g_bIsDystopia )
		return;
	
	int iEnt = -1;
	int iTeam = 0;
	while ( (iEnt = FindEntityByClassname( iEnt, "dys_team" )) != -1 ) {
		iTeam = GetEntProp( iEnt, Prop_Data, "m_Team" );
		switch ( iTeam ) {
			case TEAM_PUNKS, TEAM_CORPS: {
				g_iTeams[iTeam] = iEnt;
			}
		}
	}
	
	if ( -1 == g_iTeams[TEAM_PUNKS] ) {
		SetFailState( "Unable to find Punks team entity." );
	}
	if ( -1 == g_iTeams[TEAM_CORPS] ) {
		SetFailState( "Unable to find Corps team entity." );
	}
	
	GetPlayersPlaying();
	
	AnnounceTurboMode();
}


public void OnClientPutInServer( int client ) {
	if ( !g_bIsDystopia )
		return;
	
	if ( !g_bTurboEnabled || IsFakeClient(client) )
		return;
	
	PrintToChat( client, "%s", g_sTurboStatusStrings[g_bTurboEnabled] );
}

public void OnClientDisconnect( int client ) {
	if ( !g_bIsDystopia )
		return;
	
	g_iPlayerTeams[client] = 0;
	
	GetPlayersPlaying();
	
	AnnounceTurboMode();
}

void ConVar_TurboRequiredPlayers( ConVar convar, const char[] oldValue, const char[] newValue ) {
	g_iPlayerActivationThreshold = StringToInt(newValue);
	AnnounceTurboMode();
}

// Action TurboStatus( int client, int args ) {
	// PrintToChat(
		// client,
		// "g_iPlayersPlaying: %i; g_bTurboEnabled: %b; g_iPlayerActivationThreshold: %i",
		// g_iPlayersPlaying,
		// g_bTurboEnabled,
		// g_iPlayerActivationThreshold
	// );
	// GetPlayersPlaying();
	// PrintToChat(
		// client,
		// "GetPlayersPlaying: %i;",
		// g_iPlayersPlaying
	// );
	
	// return Plugin_Handled;
// }

// Action TurboTeam( int client, int args ) {
	// char arg1[2];
	// GetCmdArg( 1, arg1, 2 );
	// int team = StringToInt( arg1 );
	// ChangeClientTeam( client, team );
	// return Plugin_Handled;
// }

stock float CalcRespawnScale() {
	int activation_threshold = g_iPlayerActivationThreshold;
	int player_factor = 64 - g_iPlayersPlaying;
	if ( !activation_threshold && !player_factor ) {
		// activation_threshold = 1;
		return float(0);
	}

	float fRespawnScale = float( player_factor + activation_threshold ) / float(64);
	return fRespawnScale;
}

stock float GetClientRespawnBonus( int client ) {
	float fClientPenalty = 0.0;
	float fRespawnScale = 0.0;
	float fRespawnBonus = 0.0;
	char sClientModel[64];
	GetClientModel( client, sClientModel, sizeof(sClientModel) );
	
	if ( -1 != StrContains( sClientModel, "light", false ) ) {
		fClientPenalty = 2.0;
	}
	if ( -1 != StrContains( sClientModel, "medium", false ) ) {
		fClientPenalty = 3.0;
	}
	if ( -1 != StrContains( sClientModel, "heavy", false ) ) {
		fClientPenalty = 6.0;
	}
	
	if ( g_bEnableForTesting ) {
		fRespawnScale = float(g_iPlayerActivationThreshold) / float(64);
	} else {
		fRespawnScale = CalcRespawnScale();
	}
	
	fRespawnBonus = fClientPenalty - ( fClientPenalty * fRespawnScale );
	
	return fRespawnBonus;
}

stock void AwardRespawnBonus( int team, float bonus ) {
	if ( 0 > g_iTeams[team] )
		return;
	
	float fRespawnTime = GetEntPropFloat( g_iTeams[team], Prop_Send, "m_fSpawnTime" );
	
	// float fOldRespawnTime = fRespawnTime;
	
	fRespawnTime = fRespawnTime - bonus;
	SetEntPropFloat( g_iTeams[team], Prop_Send, "m_fSpawnTime", fRespawnTime );
	
	// float fRespawnScale = 0.0;
	// if ( g_bEnableForTesting ) {
		// fRespawnScale = float(g_iPlayerActivationThreshold) / float(64);
	// } else {
		// fRespawnScale = CalcRespawnScale();
	// }
	
	// PrintToChatAll(
		// "Team: %i; Old Respawn Time: %f; New Respawn Time: %f; Bonus: %f; Scale: %f",
		// team,
		// fOldRespawnTime,
		// fRespawnTime,
		// bonus,
		// fRespawnScale
	// );
}

stock int GetPlayersPlaying() {
	g_iPlayersPlaying = GetTeamClientCount(TEAM_PUNKS);
	g_iPlayersPlaying += GetTeamClientCount(TEAM_CORPS);
	
	// PrintToChatAll(
		// "players: %i;",
		// g_iPlayersPlaying
	// );
		
}

stock void AnnounceTurboMode() {
	if ( g_iPlayersPlaying > g_iPlayerActivationThreshold && !g_bTurboEnabled ) {
		g_bTurboEnabled = true;
		PrintToChatAll( "%s", g_sTurboStatusStrings[g_bTurboEnabled] );
	}
	
	if ( g_iPlayersPlaying <= g_iPlayerActivationThreshold && g_bTurboEnabled ) {
		g_bTurboEnabled = false;
		PrintToChatAll( "%s", g_sTurboStatusStrings[g_bTurboEnabled] );
	}
	
	// PrintToChatAll( "g_iPlayersPlaying: %i; g_bTurboEnabled: %b; g_iPlayerActivationThreshold: %i", g_iPlayersPlaying, g_bTurboEnabled, g_iPlayerActivationThreshold );
}

Action Event_RoundRestart( Event event, const char[] name, bool dontBroadcast ) {
	GetPlayersPlaying();
	
	AnnounceTurboMode();
}

// Action Event_RoundEnd( Event event, const char[] name, bool dontBroadcast ) {
	// g_bRoundActive = false;
// }

Action Event_PlayerDeath( Event event, const char[] name, bool dontBroadcast ) {
	// dont do anything unless we are enabled
	if ( g_iPlayersPlaying <= g_iPlayerActivationThreshold && !g_bEnableForTesting )
		return Plugin_Continue;
	
	int iClient = GetClientOfUserId( event.GetInt( "userid" ) );
	
	if ( !g_iPlayerTeams[iClient] )
		return Plugin_Continue;

	AwardRespawnBonus( g_iPlayerTeams[iClient], GetClientRespawnBonus( iClient ) );
	
	return Plugin_Continue;
}

Action Event_PlayerTeam( Event event, const char[] name, bool dontBroadcast ) {
	// disconnects handled elsewhere
	if ( event.GetBool( "disconnect" ) )
		return Plugin_Continue;
	
	int iClient = GetClientOfUserId( event.GetInt( "userid" ) );
	int iClientTeam = event.GetInt( "team" );
	int iClientOldTeam = event.GetInt( "oldteam" );
	
	// PrintToChatAll(
		// "client: %i; team: %i; oldteam: %i;",
		// iClient,
		// iClientTeam,
		// iClientOldTeam
	// );
	
	switch ( iClientTeam ) {
		case TEAM_PUNKS, TEAM_CORPS: {
			g_iPlayersPlaying += 1;
			g_iPlayerTeams[iClient] = iClientTeam;
		}
		default: {
			g_iPlayerTeams[iClient] = 0;
		}
	}
	
	switch ( iClientOldTeam ) {
		case TEAM_PUNKS, TEAM_CORPS: {
			g_iPlayersPlaying -= 1;
			// player_team gets called after player_death
			if ( g_iPlayersPlaying > g_iPlayerActivationThreshold || g_bEnableForTesting ) {
				float fRespawnBonus = GetClientRespawnBonus( iClient );
				AwardRespawnBonus( iClientOldTeam, -fRespawnBonus );
			}
		}
	}
	
	AnnounceTurboMode();
	
	return Plugin_Continue;
}

