#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <laper32>

#pragma semicolon 1
#pragma newdecls required

bool blockCommand;
int g_Collision;
ConVar cvar_bhop;
ConVar cvar_dm;
bool g_IsGhost[MAXPLAYERS+1];
bool g_dm_redie[MAXPLAYERS+1];

public Plugin myinfo =
{
    name        = "CS:GO Redie",
    author      = "Pyro, originally by MeoW",
    description = "Return as a ghost after you died.",
    version     = "3.0",
    url         = "http://steamcommunity.com/profiles/76561198051084603"
};

public void OnPluginStart()
{
    HookEvent("round_end",      Event_Round_End,    EventHookMode_Pre);
    HookEvent("round_start",    Event_Round_Start,  EventHookMode_Pre);
    HookEvent("player_spawn",   Event_Player_Spawn);
    HookEvent("player_death",   Event_Player_Death);

    RegConsoleCmd("sm_redie",   Command_Redie);
    
    cvar_bhop    = CreateConVar("sm_redie_bhop", "0", "If enabled, ghosts will be able to autobhop by holding space.");
    cvar_dm      = CreateConVar("sm_redie_dm", "0", "If enabled, using redie while alive will make you a ghost next time you die.");
    g_Collision  = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
    
    // load translation
    LoadTranslations("hideandseek.phrases");

    AddNormalSoundHook(OnNormalSoundPlayed);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
}

public void OnClientPostAdminCheck(int client)
{
    g_IsGhost[client] = false;
}

public Action Event_Round_End(Handle event, const char[] name, bool dontBroadcast) 
{
    blockCommand = false;
}

public Action Event_Round_Start(Handle event, const char[] name, bool dontBroadcast) 
{
    blockCommand = true;
    int ent = MaxClients + 1;
    while((ent = FindEntityByClassname(ent, "trigger_multiple")) != -1)
    {
        SDKHookEx(ent, SDKHook_EndTouch, brushentCollide);
        SDKHookEx(ent, SDKHook_StartTouch, brushentCollide);
        SDKHookEx(ent, SDKHook_Touch, brushentCollide);
    }
    while((ent = FindEntityByClassname(ent, "func_door")) != -1)
    {
        SDKHookEx(ent, SDKHook_EndTouch, brushentCollide);
        SDKHookEx(ent, SDKHook_StartTouch, brushentCollide);
        SDKHookEx(ent, SDKHook_Touch, brushentCollide);
    }
    while((ent = FindEntityByClassname(ent, "func_button")) != -1)
    {
        SDKHookEx(ent, SDKHook_EndTouch, brushentCollide);
        SDKHookEx(ent, SDKHook_StartTouch, brushentCollide);
        SDKHookEx(ent, SDKHook_Touch, brushentCollide);
    }

    for(int i = 1; i < MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            SDKHook(i, SDKHook_TraceAttack, OnTraceAttack);
        }
    }
}

public Action brushentCollide(int entity, int other)
{
    if (IsPlayerExist(other, false) && g_IsGhost[other])
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    if (IsValidEntity(victim))
    {
        if (g_IsGhost[victim])
        {
            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}


public Action Event_Player_Spawn(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
    if (g_IsGhost[client])
    {
        g_IsGhost[client] = false;
    }
}

public Action Hook_SetTransmit(int entity, int client)
{
    if (g_IsGhost[entity] && entity != client)
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public Action Event_Player_Death(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if (g_dm_redie[client])
    {
        g_dm_redie[client] = false;
        CreateTimer(0.1, bringback, client);
    }
    else
    {
        // PrintToChat(client, "\x01[\x03Redie\x01] \x04Type !redie into chat to respawn as a ghost.");
        TranslationPrintToChat(client, "redie announce");

        if(GetClientTeam(client) == 3)
        {
            int ent = -1;
            while((ent = FindEntityByClassname(ent, "item_defuser")) != -1)
            {
                if(IsValidEntity(ent))
                {
                    AcceptEntityInput(ent, "kill");
                }
            }
        }
    }
}

public Action bringback(Handle timer, any client)
{
    if (GetClientTeam(client) > 1)
    {
        g_IsGhost[client] = false;
        CS_RespawnPlayer(client);
        g_IsGhost[client] = true;
        int weaponIndex;
        for (int i = 0; i <= 3; i++)
        {
            if ((weaponIndex = GetPlayerWeaponSlot(client, i)) != -1)
            {
                RemovePlayerItem(client, weaponIndex);
                RemoveEdict(weaponIndex);
            }
        }
        SetEntProp(client, Prop_Send, "m_lifeState", 1);
        SetEntData(client, g_Collision, 2, 4, true);
        SetEntProp(client, Prop_Data, "m_ArmorValue", 0);
        SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);

        // PrintToChat(client, "\x01[\x03Redie\x01] \x04You are now a ghost.");
        TranslationPrintToChat(client, "redie become ghost");
    }
    else
    {
        // PrintToChat(client, "\x01[\x03Redie\x01] \x04You must be on a team.");
        TranslationPrintToChat(client, "redie must on team");
    }
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    if (g_IsGhost[client])
    {
        buttons &= ~IN_USE;
        if(GetConVarInt(cvar_bhop))
        {
            if(buttons & IN_JUMP)
            {
                if(GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1 && !(GetEntityMoveType(client) & MOVETYPE_LADDER) && !(GetEntityFlags(client) & FL_ONGROUND))
                {
                    SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
                    buttons &= ~IN_JUMP;
                }
            }
        }

        return Plugin_Changed;
    }

    return Plugin_Continue;
}

public Action Command_Redie(int client, int args)
{
    if (!IsPlayerAlive(client))
    {
        if(blockCommand)
        {
            if (GetClientTeam(client) > 1)
            {
                g_IsGhost[client] = false; //Allows them to pick up knife and gun to then have it removed from them
                CS_RespawnPlayer(client);
                g_IsGhost[client] = true;
                int weaponIndex;
                for (int i = 0; i <= 3; i++)
                {
                    if ((weaponIndex = GetPlayerWeaponSlot(client, i)) != -1)
                    {
                        RemovePlayerItem(client, weaponIndex);
                        RemoveEdict(weaponIndex);
                    }
                }
                SetEntProp(client, Prop_Send, "m_lifeState", 1);
                SetEntData(client, g_Collision, 2, 4, true);
                SetEntProp(client, Prop_Data, "m_ArmorValue", 0);
                SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);

                // PrintToChat(client, "\x01[\x03Redie\x01] \x04You are now a ghost.");
                TranslationPrintToChat(client, "redie become ghost");
            }
            else
            {
                // PrintToChat(client, "\x01[\x03Redie\x01] \x04You must be on a team.");
                TranslationPrintToChat(client, "redie must on team");
            }
        }
        else
        {
            // PrintToChat(client, "\x01[\x03Redie\x01] \x04Please wait for the new round to begin.");
            TranslationPrintToChat(client, "redie wait for new round");
        }
    }
    else
    {
        if(GetConVarInt(cvar_dm))
        {
            if(g_dm_redie[client])
            {
                // PrintToChat(client, "\x01[\x03Redie\x01] \x04You will no longer be brought back as a ghost next time you die.");
                TranslationPrintToChat(client, "redie dm bring back end");
            }
            else
            {
                // PrintToChat(client, "\x01[\x03Redie\x01] \x04You will be brought back as a ghost next time you die.");
                TranslationPrintToChat(client, "redie dm bring back");
            }
            
            g_dm_redie[client] = !g_dm_redie[client];
        }
        else
        {
            // PrintToChat(client, "\x01[\x03Redie\x01] \x04You must be dead to use redie.");
            TranslationPrintToChat(client, "redie must dead");
        }
    }

    return Plugin_Handled;
}

public Action OnWeaponCanUse(int client, int weapon)
{
    if(g_IsGhost[client])
        return Plugin_Handled;
    
    return Plugin_Continue;
}

public Action OnNormalSoundPlayed(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if(IsPlayerExist(entity, false) && g_IsGhost[entity])
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

#define TRANSLATION_PHRASE_PREFIX          "[HNS]"

#define TRANSLATION_TEXT_COLOR_DEFAULT     "\x01"
#define TRANSLATION_TEXT_COLOR_RED         "\x02"
#define TRANSLATION_TEXT_COLOR_LGREEN      "\x03"
#define TRANSLATION_TEXT_COLOR_GREEN       "\x04"

stock void TranslationPluginFormatString(char[] sText, int iMaxlen, bool bColor = true)
{
    if (bColor)
    {
        // Format prefix onto the string
        Format(sText, iMaxlen, " @green%s @default%s", TRANSLATION_PHRASE_PREFIX, sText);

        // Replace color tokens with CS:GO color chars
        ReplaceString(sText, iMaxlen, "@default", TRANSLATION_TEXT_COLOR_DEFAULT);
        ReplaceString(sText, iMaxlen, "@red", TRANSLATION_TEXT_COLOR_RED);
        ReplaceString(sText, iMaxlen, "@lgreen", TRANSLATION_TEXT_COLOR_LGREEN);
        ReplaceString(sText, iMaxlen, "@green", TRANSLATION_TEXT_COLOR_GREEN);
    }
    else
    {
        // Format prefix onto the string
        Format(sText, iMaxlen, "%s %s", TRANSLATION_PHRASE_PREFIX, sText);
    }
}

stock void TranslationPrintToChat(int client, any ...)
{
    // Validate real client
    if (!IsFakeClient(client))
    {
        // Sets translation target
        SetGlobalTransTarget(client);

        // Translate phrase
        static char sTranslation[CHAT_LINE_LENGTH];
        VFormat(sTranslation, CHAT_LINE_LENGTH, "%t", 2);

        // Format string to create plugin style
        TranslationPluginFormatString(sTranslation, CHAT_LINE_LENGTH);

        // Print translated phrase to the client chat
        PrintToChat(client, sTranslation);
    }
}

stock void TranslationPrintToChatAll(any ...)
{
    // i = client index
    for (int i = 1; i <= MaxClients; i++)
    {
        // Validate client
        if (!IsPlayerExist(i, false))
        {
            continue;
        }
        
        // Validate real client
        if (!IsFakeClient(i))
        {
            // Sets translation target
            SetGlobalTransTarget(i);
            
            // Translate phrase
            static char sTranslation[CHAT_LINE_LENGTH];
            VFormat(sTranslation, CHAT_LINE_LENGTH, "%t", 1);
            
            // Format string to create plugin style
            TranslationPluginFormatString(sTranslation, CHAT_LINE_LENGTH);
            
            // Print translated phrase to the client chat
            PrintToChat(i, sTranslation);
        }
    }
}

stock void TranslationPrintHintText(int client, any ...)
{
    // Validate real client
    if (!IsFakeClient(client))
    {
        // Sets translation target
        SetGlobalTransTarget(client);

        // Translate phrase
        static char sTranslation[CHAT_LINE_LENGTH];
        VFormat(sTranslation, CHAT_LINE_LENGTH, "%t", 2);

        // Print translated phrase to the client screen
        UTIL_CreateClientHint(client, sTranslation);
    }
}

stock void TranslationPrintHintTextAll(any ...)
{
    // i = client index
    for (int i = 1; i <= MaxClients; i++)
    {
        // Validate client
        if (!IsPlayerExist(i, false))
        {
            continue;
        }
        
        // Validate real client
        if (!IsFakeClient(i))
        {
            // Sets translation target
            SetGlobalTransTarget(i);
            
            // Translate phrase
            static char sTranslation[CHAT_LINE_LENGTH];
            VFormat(sTranslation, CHAT_LINE_LENGTH, "%t", 1);
            
            // Print translated phrase to the client screen
            UTIL_CreateClientHint(i, sTranslation);
        }
    }
}

stock void TranslationPrintHudText(Handle hSync, int client, float x, float y, float holdTime, int r, int g, int b, int a, int effect, float fxTime, float fadeIn, float fadeOut, any ...)
{
    // Validate real client
    if (!IsFakeClient(client))
    {
        // Sets translation target
        SetGlobalTransTarget(client);

        // Translate phrase
        static char sTranslation[CHAT_LINE_LENGTH];
        VFormat(sTranslation, CHAT_LINE_LENGTH, "%t", 14);

        // Print translated phrase to the client screen
        UTIL_CreateClientHud(hSync, client, x, y, holdTime, r, g, b, a, effect, fxTime, fadeIn, fadeOut, sTranslation);
    }
}

stock void TranslationPrintHudTextAll(Handle hSync, float x, float y, float holdTime, int r, int g, int b, int a, int effect, float fxTime, float fadeIn, float fadeOut, any ...)
{
    // i = client index
    for (int i = 1; i <= MaxClients; i++)
    {
        // Validate client
        if (!IsPlayerExist(i, false))
        {
            continue;
        }
        
        // Validate real client
        if (!IsFakeClient(i))
        {
            // Sets translation target
            SetGlobalTransTarget(i);
            
            // Translate phrase
            static char sTranslation[CHAT_LINE_LENGTH];
            VFormat(sTranslation, CHAT_LINE_LENGTH, "%t", 13);

            // Print translated phrase to the client screen
            UTIL_CreateClientHud(hSync, i, x, y, holdTime, r, g, b, a, effect, fxTime, fadeIn, fadeOut, sTranslation);
        }
    }
}