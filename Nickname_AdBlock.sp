#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <regex>

#define PLUGIN_VERSION "0.6"
#define CVAR_FLAGS FCVAR_NOTIFY

char Logfile[PLATFORM_MAX_PATH];
Handle g_iTimerList[MAXPLAYERS + 1] = {null, ...};
ConVar cvar_PluginEnabled, cvar_PluginMode, cvar_WarningMode;
Handle g_Regex = null;
int g_iPluginMode = 0, g_iWarningMode = 0, g_iKickedClients = 0;
bool bHooked = false;

public Plugin myinfo = 
{
    name           = "Nickname AdBlock",
    author         = "FeedBlack",
    description    = "Kicks user if his nickname contains advertisement.",
    version        = PLUGIN_VERSION,
    url            = "https://steamcommunity.com/id/feedblackg44",
};

public void OnPluginStart()
{
	CreateConVar("l4d2_glow_survivor_version", PLUGIN_VERSION, "[L4D2] Glow Survivor plugin version", CVAR_FLAGS|FCVAR_DONTRECORD);
	cvar_PluginEnabled = CreateConVar("sm_nnadblock_enabled", "1", "1 - Enabled, 0 - Disabled.", CVAR_FLAGS, true, 0.0, true, 1.0);
	cvar_PluginMode = CreateConVar("sm_nnadblock_mode", "1", "1 - checks players every round, 2 - checks players when they connect to the server, 3 - checks players in both situations.", CVAR_FLAGS, true, 0.0, true, 3.0);
	cvar_WarningMode = CreateConVar("sm_nnadblock_warning_mode", "2", "1 - warning comes in the center of client's screen, 2 - warning comes in chat, 0 - Disabled, kicks users immediately on round starts.", CVAR_FLAGS, true, 0.0, true, 2.0);

	AutoExecConfig(true, "sm_nnadblock");

	cvar_PluginEnabled.AddChangeHook(OnConVarEnableChanged);
	cvar_PluginMode.AddChangeHook(OnConVarsChanged);
	cvar_WarningMode.AddChangeHook(OnConVarsChanged);

	BuildPath(Path_SM, Logfile, sizeof(Logfile), "logs/nnadblock.log");

	RegAdminCmd("sm_kickunallowed", KickUnallowedCommand, ADMFLAG_KICK);
	RegAdminCmd("sm_kickunallow", KickUnallowedCommand, ADMFLAG_KICK);

	LoadTranslations("nnadblock.phrases");

	g_Regex = CompileRegex("\\.(ru|net|ua|tf|com|org|su|cash|trade|co|uk)");
}

public void OnConfigsExecuted()
{
	IsAllowed();
}

void OnConVarEnableChanged(ConVar cvar, const char[] oldVal, const char[] newVal)
{
	IsAllowed();
}

void OnConVarsChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_iPluginMode = cvar_PluginMode.IntValue;
	g_iWarningMode = cvar_WarningMode.IntValue;
}

void IsAllowed()
{
	bool bPluginOn = cvar_PluginEnabled.BoolValue;
	if(!bHooked && bPluginOn)
	{
		bHooked = true;
		OnConVarsChanged(null, "", "");
		HookEvent("teamplay_round_start", OnRoundStart, EventHookMode_PostNoCopy);
	}
	else if(bHooked && !bPluginOn)
	{
		bHooked = false;
		UnhookEvent("teamplay_round_start", OnRoundStart, EventHookMode_PostNoCopy);
		for (int i = 1; i <= MaxClients; i++)
		{
			if(g_iTimerList[i] != null)
			{
				delete g_iTimerList[i];
			}
		}
	}
}

void KickUnallowed(int iClient)
{
	if(iClient > 0 && IsClientInGame(iClient) && !IsFakeClient(iClient))
	{
		char szUsername[MAX_NAME_LENGTH], szUserID[MAX_TARGET_LENGTH];
		GetClientName(iClient, szUsername, sizeof(szUsername));
		GetClientAuthId(iClient, AuthId_Steam3, szUserID, sizeof(szUserID));
		if (MatchRegex(g_Regex, szUsername) > 0)
		{
			KickClient(iClient, "%t", "nnad_kickreason");
			PrintToChatAll("%s %t", szUsername, "nnad_kickmessage");
			LogToFile(Logfile, "%s has been kicked due to unallowed nickname! Client id: %s", szUsername, szUserID);
			g_iKickedClients++;
		}
	}
}

Action OnRoundStart(Event hEvent, const char[] szEventName, bool bDontBroadcast)
{
	if (g_iPluginMode == 1 || g_iPluginMode == 3)
	{
		for (int iClientCheck = 1; iClientCheck <= MaxClients; iClientCheck++)
		{
			if (g_iWarningMode > 0)
			{
				if(g_iTimerList[iClientCheck] != null)
				{
					delete g_iTimerList[iClientCheck];
				}

				char szUsername[MAX_NAME_LENGTH];
				GetClientName(iClientCheck, szUsername, sizeof(szUsername));
				if (MatchRegex(g_Regex, szUsername) > 0)
				{
					if (g_iWarningMode == 1)
					{
						SetHudTextParams(-1.0, -1.0, 10.0, 255, 255, 255, 255);
						ShowHudText(iClientCheck, -1, "%t!", "nnad_warningmessage");
					}
					else if (g_iWarningMode == 2)
					{
						PrintToChat(iClientCheck, "[NNAD] %t.", "nnad_warningmessage");
					}
				}

				g_iTimerList[iClientCheck] = CreateTimer(300.0, KickUnallowedAction, iClientCheck);
			}
			else
			{
				KickUnallowed(iClientCheck);
			}
		}
	}
	return Plugin_Continue;
}

public void OnClientConnected(int iClientCheck)
{
	if (bHooked && (g_iPluginMode == 2 || g_iPluginMode == 3))
	{
		KickUnallowed(iClientCheck);
	}
}

Action KickUnallowedAction(Handle hTimer, int iClientCheck)
{
	if(bHooked)
	{
		int iClient = GetClientOfUserId(iClientCheck);
		if(iClient > 0 && IsClientInGame(iClient) && !IsFakeClient(iClient))
		{
			KickUnallowed(iClient);
		}
	}
	return Plugin_Stop;
}

Action KickUnallowedCommand(int iClientAdmin, int args) 
{
	if(bHooked)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			KickUnallowed(i);
		}
		PrintToConsole(iClientAdmin, "%i clients has been kicked.", g_iKickedClients);
		g_iKickedClients = 0;
	}
	else
	{
		PrintToConsole(iClientAdmin, "Nickname AdBlock is Disabled!");
	}
	return Plugin_Handled;
}
