#pragma semicolon               1
#pragma newdecls                required

#include <sourcemod>
#include <colors>

#undef REQUIRE_PLUGIN
#include <left4dhooks>
#define REQUIRE_PLUGIN


public Plugin myinfo = {
    name        = "TeamSwitchControl",
    author      = "TouchMe",
    description = "A plugin to manage team switching",
    version     = "build_0002",
    url         = "https://github.com/TouchMe-Inc/l4d2_team_switch_control"
};


#define TRANSLATIONS            "team_switch_control.phrases"

/**
 * Libs.
 */
#define LIB_DHOOK               "left4dhooks"

/*
 * Infected class.
 */
#define CLASS_TANK              8

/**
 * Teams.
 */
#define TEAM_NONE               0
#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

/**
 * Sugar.
 */
 #define SetHumanSpec            L4D_SetHumanSpec
 #define TakeOverBot             L4D_TakeOverBot


bool g_bDHookAvailable = false;

// ConVar g_cvSurvivorLimit = null;
// ConVar g_cvMaxPlayerZombues = null;

ConVar g_cvSwitchTeamCooldown = null;
int g_iSwitchTeamCooldown = 0;

int g_iLastClientCommandTime[MAXPLAYERS + 1] = {0, ...};


/**
 * Called before OnPluginStart.
 */
public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] sErr, int iErrLen)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(sErr, iErrLen, "Plugin only supports Left 4 Dead 2");
        return APLRes_SilentFailure;
    }

    return APLRes_Success;
}

/**
* Global event. Called when all plugins loaded.
*/
public void OnAllPluginsLoaded()
{
    g_bDHookAvailable = LibraryExists(LIB_DHOOK);
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, LIB_DHOOK)) {
        g_bDHookAvailable = true;
    }
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName)
{
    if (StrEqual(sName, LIB_DHOOK)) {
        g_bDHookAvailable = false;
    }
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
    LoadTranslations(TRANSLATIONS);

    RegConsoleCmd("sm_spectate", Cmd_Spectate, "Moves you to the spectator team");
    RegConsoleCmd("sm_spec", Cmd_Spectate, "Moves you to the spectator team");
    RegConsoleCmd("sm_s", Cmd_Spectate, "Moves you to the spectator team");

    g_cvSwitchTeamCooldown = CreateConVar("sm_tsc_cooldown", "5.0");

    g_iSwitchTeamCooldown = GetConVarInt(g_cvSwitchTeamCooldown);

    AddCommandListener(Listener_JoinTeam, "jointeam");
}

Action Cmd_Spectate(int iClient, int iArgs)
{
    int iCurrentTime = GetTime();
    int iDelay = g_iLastClientCommandTime[iClient] - iCurrentTime;

    if (iDelay > 0)
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "TEAM_SWITCH_DELAY", iClient, iDelay);
        return Plugin_Handled;
    }

    switch (GetClientTeam(iClient))
    {
        case TEAM_SURVIVOR: SetupClientTeam(iClient, TEAM_SPECTATOR);
        
        case TEAM_INFECTED:
        {
            if (IsInfectedTank(iClient))
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "TEAM_SWITCH_FOR_TANK_BLOCKED", iClient);
                return Plugin_Handled;
            }

            if (IsInfectedWithVictim(iClient))
            {
                CPrintToChat(iClient, "%T%T", "TAG", iClient, "TEAM_SWITCH_WITH_VICTIM_BLOCKED", iClient);
                return Plugin_Handled;
            }

            else if (!IsInfectedGhost(iClient)) {
                ForcePlayerSuicide(iClient);
            }

            SetupClientTeam(iClient, TEAM_SPECTATOR);
        }

        case TEAM_SPECTATOR: RespectateClient(iClient);
    }

    g_iLastClientCommandTime[iClient] = iCurrentTime + g_iSwitchTeamCooldown;
    
    return Plugin_Handled;
}

Action Listener_JoinTeam(int iClient, const char[] command, int iArgs)
{
    if (!iArgs || !IsClientInGame(iClient)) {
        return Plugin_Handled;
    }

    int iCurrentTime = GetTime();
    int iDelay = g_iLastClientCommandTime[iClient] - iCurrentTime;

    if (iDelay > 0)
    {
        CPrintToChat(iClient, "%T%T", "TAG", iClient, "TEAM_SWITCH_DELAY", iClient, iDelay);
        return Plugin_Handled;
    }

    if (IsClientInfected(iClient))
    {
        if (IsInfectedTank(iClient))
        {
            CPrintToChat(iClient, "%T%T", "TAG", iClient, "TEAM_SWITCH_FOR_TANK_BLOCKED", iClient);
            return Plugin_Handled;
        }

        if (IsInfectedWithVictim(iClient))
        {
            CPrintToChat(iClient, "%T%T", "TAG", iClient, "TEAM_SWITCH_WITH_VICTIM_BLOCKED", iClient);
            return Plugin_Handled;
        }
    }

    g_iLastClientCommandTime[iClient] = iCurrentTime + g_iSwitchTeamCooldown;

    return Plugin_Continue;
}

/**
 * A hack that switches the player to the infected team and back to the observers.
 */
void RespectateClient(int iClient)
{
    ChangeClientTeam(iClient, TEAM_INFECTED);
    CreateTimer(0.1, Timer_TurnClientToSpectate, iClient, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer for switch team.
 */
Action Timer_TurnClientToSpectate(Handle timer, int iClient)
{
    if (IsClientInGame(iClient) && !IsFakeClient(iClient)) {
        ChangeClientTeam(iClient, TEAM_SPECTATOR);
    }

    return Plugin_Stop;
}

/**
 * Sets the client team.
 *
 * @param iClient           Client index.
 * @param iTeam             Client team.
 * @return                  Returns true if success.
 */
bool SetupClientTeam(int iClient, int iTeam)
{
    if (GetClientTeam(iClient) == iTeam) {
        return true;
    }

    if (iTeam == TEAM_INFECTED || iTeam == TEAM_SPECTATOR)
    {
        ChangeClientTeam(iClient, iTeam);
        return true;
    }

    int iBot = FindSurvivorBot();
    if (iTeam == TEAM_SURVIVOR && iBot != -1)
    {
        if (g_bDHookAvailable)
        {
            ChangeClientTeam(iClient, TEAM_NONE);
            SetHumanSpec(iBot, iClient);
            TakeOverBot(iClient);
        }

        else {
            ExecuteCheatCommand(iClient, "sb_takecontrol");
        }

        return true;
    }

    return false;
}

/**
 * Hack to execute cheat commands.
 */
void ExecuteCheatCommand(int iClient, const char[] sCmd, const char[] sArgs = "")
{
    int iFlags = GetCommandFlags(sCmd);
    SetCommandFlags(sCmd, iFlags & ~FCVAR_CHEAT);
    FakeClientCommand(iClient, "%s %s", sCmd, sArgs);
    SetCommandFlags(sCmd, iFlags);
}

/**
 * Finds a free bot.
 *
 * @return                  Bot index, otherwise -1.
 */
int FindSurvivorBot()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient)
        || !IsFakeClient(iClient)
        || !IsClientSurvivor(iClient)) {
            continue;
        }

        return iClient;
    }

    return -1;
}

/**
 * Checks if the client is on the Survivor team.
 *
 * @param iClient           The client identifier.
 *
 * @return                  true if the client is a Survivor, otherwise false.
 */
bool IsClientSurvivor(int iClient) {
    return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

/**
 * Checks if the client is on the Infected team.
 *
 * @param iClient           The client identifier.
 *
 * @return                  true if the client is Infected, otherwise false.
 */
bool IsClientInfected(int iClient) {
    return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Get the zombie player class.
 */
int GetInfectedClass(int iClient) { 
    return GetEntProp(iClient, Prop_Send, "m_zombieClass"); 
}

bool IsInfectedTank(int iClient) { 
    return GetInfectedClass(iClient) == CLASS_TANK; 
}

/**
 * Returns whether the player is a ghost.
 */
bool IsInfectedGhost(int iClient) {
	return view_as<bool>(GetEntProp(iClient, Prop_Send, "m_isGhost"));
}

/**
 * Checks if the Infected client has a victim.
 *
 * @param iClient           The client identifier.
 *
 * @return                  true if the client has a victim, otherwise false.
 */
bool IsInfectedWithVictim(int iClient) {
    return GetEntProp(iClient, Prop_Send, "m_tongueVictim") > 0
    || GetEntProp(iClient, Prop_Send, "m_pounceVictim") > 0
    || GetEntProp(iClient, Prop_Send, "m_pummelVictim") > 0
    || GetEntProp(iClient, Prop_Send, "m_jockeyVictim") > 0
    || GetEntPropEnt(iClient, Prop_Send, "m_carryVictim") > 0;
}
