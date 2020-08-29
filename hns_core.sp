#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <utils>

#define LoopAllAlivePlayers(%1) for(int %1=1;%1<=MaxClients;++%1)\
if(IsPlayerExist(%1))

#define LoopAllPlayers(%1) for(int %1=1;%1<=MaxClients;++%1)\
if(IsPlayerExist(%1, false))

EngineVersion g_Game;

public Plugin myinfo = 
{
    name = "[HNS] Core",
    author = "Kroytz",
    description = "Hide and seek",
    version = "1.0 Alpha",
    url = "http://github.com/Kroytz"
};

#define GAMEPLAY_COUNTDOWN 10
#define GAMEPLAY_ALLOWSLASH 3
#define GAMEPLAY_FORCESWAP 5

enum struct ServerData
{
    bool NewRound;
    bool RoundEnd;

    int Countdown;
    int TotalLose;

    Handle CountdownTimer;

    Handle AnnounceSync;

    void Reset()
    {
        this.NewRound = false;
        this.RoundEnd = false;

        this.Countdown = 0;
        this.TotalLose = 0;
    }

    void PurgeTimers()
    {
        this.CountdownTimer = null;
    }
}
ServerData gServerData;

public void OnPluginStart()
{
    // engine is csgo?
    g_Game = GetEngineVersion();
    if(g_Game != Engine_CSGO)
        SetFailState("This plugin is for CS:GO only.");	

    // event hooks
    HookEvent("round_start", Event_OnRoundStart);
    HookEvent("round_end", Event_OnRoundEnd);
    HookEvent("player_spawn", Event_OnPlayerSpawn, EventHookMode_Post);
    HookEvent("player_team", Event_OnPlayerTeam, EventHookMode_Pre);

    // load translation
    LoadTranslations("hideandseek.phrases");

    // hud sync
    gServerData.AnnounceSync = CreateHudSynchronizer();

    // team manager
    AddCommandListener(OnJoinTeamListened, "jointeam");
}

public void OnMapEnd()
{
    gServerData.PurgeTimers();
}

public void OnClientPostAdminCheck(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public Action OnJoinTeamListened(int client, const char[] command, int argc)
{
    if (!IsPlayerExist(client, false) || argc < 1)
        return Plugin_Handled;

    char arg[4];
    GetCmdArg(1, arg, 4);
    int newteam = StringToInt(arg);
    int oldteam = GetClientTeam(client);

    if ((oldteam <= CS_TEAM_SPECTATOR) || (newteam <= CS_TEAM_SPECTATOR))
    {
        return Plugin_Continue;
    }

    // team?
    if (newteam == oldteam)
        return Plugin_Handled;

    return Plugin_Handled;
}

void GamesKillEntities()
{
    // Initialize name char
    static char sClassname[NORMAL_LINE_LENGTH];
    
    // i = entity index
    int MaxEntities = GetMaxEntities();
    for (int i = MaxClients; i <= MaxEntities; i++)
    {
        // Validate entity
        if (IsValidEdict(i))
        {
            // Gets valid edict classname
            GetEdictClassname(i, sClassname, sizeof(sClassname));

            // Validate objectives
            if ((sClassname[0] == 'h' && sClassname[7] == '_' && sClassname[8] == 'e') || // hostage_entity
               (sClassname[0] == 'f' && // func_
               (sClassname[5] == 'h' || // _hostage_rescue
               (sClassname[5] == 'b' && (sClassname[7] == 'y' || sClassname[7] == 'm'))))) // _buyzone , _bomb_target
            {
                AcceptEntityInput(i, "Kill"); /// Destroy
            }
            // Validate weapon
            else if (sClassname[0] == 'w' && sClassname[1] == 'e' && sClassname[6] == '_')
            {
                // Gets weapon owner
                int client = GetEntPropEnt(i, Prop_Send, "m_hOwner");
                    
                // Validate owner
                if (!IsPlayerExist(client))
                {
                    AcceptEntityInput(i, "Kill"); /// Destroy
                }
            }
        }
    }
}

public Action Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    GamesKillEntities();

    if(GameRules_GetProp("m_bWarmupPeriod"))
    {
        return Plugin_Continue;
    }

    gServerData.RoundEnd = false;
    gServerData.NewRound = true;

    gServerData.Countdown = GAMEPLAY_COUNTDOWN;

    delete gServerData.CountdownTimer;
    gServerData.CountdownTimer = CreateTimer(1.0, timerGameStart, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Continue;
}

public Action timerGameStart(Handle timer)
{
    static int team;

    if (gServerData.Countdown > 0)
    {
        gServerData.Countdown --;
        // TranslationPrintHintTextAll("hns countdown", gServerData.Countdown);

        TranslationPrintHudTextAll(
            gServerData.AnnounceSync,
            -1.0,
            0.82,
            1.0,
            0, 128, 255, 150,
            1,
            0.1,
            0.35, 0.35,
            "hns countdown", 
            gServerData.Countdown);

        LoopAllAlivePlayers(i)
        {
            team = GetClientTeam(i);
            if (team == CS_TEAM_CT)
                UTIL_CreateFadeScreen(i, 0.2, 1.0, FFADE_IN | FFADE_PURGE, {240, 255, 255, 100});
        }

        return Plugin_Continue;
    }

    gServerData.NewRound = false;

    LoopAllAlivePlayers(i)
    {
        team = GetClientTeam(i);
        GamesGiveEquipment(i, team);
    }

    // TranslationPrintHintTextAll("hns roundstart");
    TranslationPrintHudTextAll(
        gServerData.AnnounceSync,
        -1.0,
        0.82,
        5.0,
        0, 128, 255, 150,
        1,
        0.1,
        0.35, 0.35,
        "hns roundstart");

    gServerData.CountdownTimer = null;
    return Plugin_Stop;
}

public Action Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("winner");

    if (winner == CS_TEAM_CT)
    {
        gServerData.TotalLose = 0;

        // TranslationPrintHintTextAll("hns seekers win");
        TranslationPrintHudTextAll(
            gServerData.AnnounceSync,
            -1.0,
            0.82,
            5.0,
            0, 128, 255, 150,
            1,
            0.1,
            0.35, 0.35,
            "hns seekers win");
        GamesSwapTeam();
    }
    else
    {
        gServerData.TotalLose ++;

        TranslationPrintHudTextAll(
            gServerData.AnnounceSync,
            -1.0,
            0.82,
            5.0,
            0, 128, 255, 150,
            1,
            0.1,
            0.35, 0.35,
            "hns hiders win");

        if (gServerData.TotalLose > GAMEPLAY_FORCESWAP)
        {
            gServerData.TotalLose = 0;
            GamesSwapTeam();
            TranslationPrintHintTextAll("hns force swap", gServerData.TotalLose);
        }
        else if (gServerData.TotalLose >= GAMEPLAY_ALLOWSLASH)
        {
            TranslationPrintToChatAll("hns allow slash", gServerData.TotalLose);
        }
    }

    gServerData.RoundEnd = true;
    delete gServerData.CountdownTimer;
}

public Action Hook_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
    if (IsPlayerExist(attacker))
    {
        int iTeam = GetClientTeam(attacker);
        switch (iTeam)
        {
            case CS_TEAM_T: return Plugin_Handled;
            case CS_TEAM_CT:
            {
                if (IsBackstabDamage(damage))
                {
                    damage *= 0.5;
                }

                int iHealth = ToolsGetHealth(victim);
                if (float(iHealth) > damage)
                {
                    ToolsSetHealth(victim, iHealth - RoundFloat(damage));
                    return Plugin_Handled;
                }
                else
                {
                    return Plugin_Changed;
                }
            }
        }
    }

    return Plugin_Continue;
}

public Action Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int userID = event.GetInt("userid");
    int client = GetClientOfUserId(userID);
    int team = event.GetInt("teamnum");

    if (IsPlayerExist(client))
    {
        RequestFrame(SetClientRadar, userID);

        // Stip weapon first
        StripWeapon(client, true);

        // Free armor
        SetEntProp(client, Prop_Send, "m_ArmorValue", 100);
        SetEntProp(client, Prop_Send, "m_bHasHelmet", true);

        switch (team)
        {
            case CS_TEAM_CT:
            {
                TranslationPrintHintText(client, "hns seeker info");
            }

            case CS_TEAM_T:
            {
                TranslationPrintHintText(client, "hns hider info");
            }
        }

        if(GameRules_GetProp("m_bWarmupPeriod"))
            return Plugin_Continue;

        if (gServerData.Countdown <= 0)
        {
            if ((!gServerData.NewRound) && (!gServerData.RoundEnd))
            {
                // Give equipment
                GamesGiveEquipment(client, team);
            }
        }
    }

    return Plugin_Continue;
}

public Action Event_OnPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    return Plugin_Handled;
}

static void SetClientRadar(int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsPlayerExist(client))
    {
        SetEntProp(client, Prop_Send, "m_iHideHUD", HIDEHUD_RADAR);
    }
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    if (IsPlayerExist(client))
    {
        if (GetClientTeam(client) == CS_TEAM_CT)
        {
            if(GameRules_GetProp("m_bWarmupPeriod"))
            {
                return Plugin_Continue;
            }

            if ((gServerData.Countdown >= 0) && (gServerData.NewRound))
            {
                return Plugin_Handled;
            }

            if (gServerData.TotalLose < GAMEPLAY_ALLOWSLASH)
            {
                // Validate weapon
                if ((buttons & IN_ATTACK))    // Knife + slash?
                {
                    buttons &= ~(IN_ATTACK);   // Use stab instead
                    buttons |= IN_ATTACK2;
                    return Plugin_Changed;
                }
            }
        }

        // Duck speed fix: Set to default velocity.
        if (buttons & IN_DUCK)
        {
            // Set to default (8.0).
            SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", 8.0);
        }
    }

    return Plugin_Continue;
}

void GamesGiveEquipment(int client, int team)
{
    switch(team)
    {
        case CS_TEAM_CT:
        {
            // Give knife
            GivePlayerItem(client, "weapon_knife");
        }

        case CS_TEAM_T:
        {
            // Give nades
            GivePlayerItem(client, "weapon_smokegrenade");
            GivePlayerItem(client, "weapon_flashbang");

            // Give knife for fix
            GivePlayerItem(client, "weapon_knife");
        }
    }
}

void GamesSwapTeam()
{
    static int team;
    LoopAllPlayers(i)
    {
        team = GetClientTeam(i);

        switch (team)
        {
            case CS_TEAM_CT:
            {
                CS_SwitchTeam(i, CS_TEAM_T);
            }

            case CS_TEAM_T:
            {
                CS_SwitchTeam(i, CS_TEAM_CT);
            }
        }
    }
}

stock void StripWeapon(int client, bool suit = false)
{
    int stripper = CreateEntityByName("player_weaponstrip"); 
    if(stripper == -1)
        ThrowNativeError(SP_ERROR_NATIVE, "Create player_weaponstrip failed.");
    
    AcceptEntityInput(stripper, !suit ? "Strip" : "StripWeaponsAndSuit", client);
    AcceptEntityInput(stripper, "Kill");
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

stock bool IsBackstabDamage(float damage)
{
    //LS -> 40 | RS -> 65 | LB -> 90 | RB -> 180
    if(damage == 90.0 || damage == 180.0)
        return true;
    else
        return false;
}

int ToolsGetHealth(int entity, bool bMax = false)
{
    // Gets health of the entity
    return GetEntProp(entity, Prop_Data, bMax ? "m_iMaxHealth" : "m_iHealth");
}

void ToolsSetHealth(int entity, int iValue, bool bSet = false)
{
    // Sets health of the entity
    SetEntProp(entity, Prop_Send, "m_iHealth", iValue);
    
    // If set is true, then set max health
    if (bSet) 
    {
        // Sets max health of the entity
        SetEntProp(entity, Prop_Data, "m_iMaxHealth", iValue);
    }
}

stock void fnInitGameConfOffset(Handle gameConf, int &iOffset, char[] sKey)
{
    // Validate offset
    if ((iOffset = GameConfGetOffset(gameConf, sKey)) == -1)
    {
        SetFailState("[GameData Validation] Failed to get offset: \"%s\"", sKey);
    }
}