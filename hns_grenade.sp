#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

#define FLASH 0
#define SMOKE 1

#define SOUND_FREEZE    "physics/glass/glass_impact_bullet4.wav"
#define SOUND_FREEZE_EXPLODE    "ui/freeze_cam.wav"

#define FragColor     {255,75,75,255}
#define FlashColor     {255,255,255,255}
#define SmokeColor    {75,255,75,255}
#define FreezeColor    {75,75,255,255}

int BeamSprite, GlowSprite, g_beamsprite, g_halosprite;

ConVar h_greneffects_enable; bool b_enable;
ConVar h_greneffects_trails; bool b_trails;
ConVar h_greneffects_smoke_freeze; bool b_smoke_freeze;
ConVar h_greneffects_smoke_freeze_distance; float f_smoke_freeze_distance;
ConVar h_greneffects_smoke_freeze_duration; float f_smoke_freeze_duration;

Handle h_freeze_timer[MAXPLAYERS+1];

public Plugin myinfo = 
{
    name = "[HNS] Grenade Effects",
    author = "FrozDark (HLModders.ru LLC) & Franc1sco franug & Kroytz",
    description = "Adds Grenades Special Effects.",
    version = "2.3.1 CSGO fix by Franc1sco franug",
    url = "http://github.com/Kroytz"
}

public void OnPluginStart()
{
    // Register cvar
    h_greneffects_enable = CreateConVar("hns_greneffect_enable", "1", "Enables/Disables the plugin", 0, true, 0.0, true, 1.0);
    h_greneffects_trails = CreateConVar("hns_greneffect_trails", "1", "Enables/Disables Grenade Trails", 0, true, 0.0, true, 1.0);
    
    h_greneffects_smoke_freeze = CreateConVar("hns_greneffect_smoke_freeze", "1", "Changes a smoke grenade to a freeze grenade", 0, true, 0.0, true, 1.0);
    h_greneffects_smoke_freeze_distance = CreateConVar("hns_greneffect_smoke_freeze_distance", "300", "The freeze grenade distance", 0, true, 100.0);
    h_greneffects_smoke_freeze_duration = CreateConVar("hns_greneffect_smoke_freeze_duration", "4", "The freeze duration in seconds", 0, true, 1.0);
    
    // Load cvar
    b_enable = GetConVarBool(h_greneffects_enable);
    b_trails = GetConVarBool(h_greneffects_trails);

    b_smoke_freeze = GetConVarBool(h_greneffects_smoke_freeze);
    f_smoke_freeze_distance = GetConVarFloat(h_greneffects_smoke_freeze_distance);
    f_smoke_freeze_duration = GetConVarFloat(h_greneffects_smoke_freeze_duration);

    // Hook cvar change
    HookConVarChange(h_greneffects_enable, OnConVarChanged);
    HookConVarChange(h_greneffects_trails, OnConVarChanged);
    HookConVarChange(h_greneffects_smoke_freeze, OnConVarChanged);
    HookConVarChange(h_greneffects_smoke_freeze_distance, OnConVarChanged);
    HookConVarChange(h_greneffects_smoke_freeze_duration, OnConVarChanged);

    // Hook event
    HookEvent("round_start", OnRoundStart);
    HookEvent("player_death", OnPlayerDeath);
    AddNormalSoundHook(NormalSHookCB);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == h_greneffects_enable)
    {
        b_enable = view_as<bool>(StringToInt(newValue));
    }
    else if (convar == h_greneffects_trails)
    {
        b_trails = view_as<bool>(StringToInt(newValue));
    }
    else if (convar == h_greneffects_smoke_freeze)
    {
        b_smoke_freeze = view_as<bool>(StringToInt(newValue));
    }
    else if (convar == h_greneffects_smoke_freeze_distance)
    {
        f_smoke_freeze_distance = StringToFloat(newValue);
    }
    else if (convar == h_greneffects_smoke_freeze_duration)
    {
        f_smoke_freeze_duration = StringToFloat(newValue);
    }
}

public void OnMapStart()
{
    BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
    GlowSprite = PrecacheModel("materials/sprites/blueglow1.vmt");
    g_beamsprite = PrecacheModel("materials/sprites/laserbeam.vmt");
    g_halosprite = PrecacheModel("materials/sprites/halo.vmt");
    
    PrecacheSound(SOUND_FREEZE);
    PrecacheSound(SOUND_FREEZE_EXPLODE);
}

public void OnClientDisconnect(int client)
{
    if (IsClientInGame(client))
        ExtinguishEntity(client);
    
    if (h_freeze_timer[client] != INVALID_HANDLE)
    {
        KillTimer(h_freeze_timer[client]);
        h_freeze_timer[client] = INVALID_HANDLE;
    }
}

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (h_freeze_timer[client] != INVALID_HANDLE)
        {
            KillTimer(h_freeze_timer[client]);
            h_freeze_timer[client] = INVALID_HANDLE;
        }
    }
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    OnClientDisconnect(GetClientOfUserId(GetEventInt(event, "userid")));
}

void GranadaCongela(int client, float origin[3])
{
    origin[2] += 10.0;
    
    float targetOrigin[3];
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i) || (GetClientTeam(i) == CS_TEAM_T))
        {
            continue;
        }
        
        GetClientAbsOrigin(i, targetOrigin);
        targetOrigin[2] += 2.0;
        if (GetVectorDistance(origin, targetOrigin) <= f_smoke_freeze_distance)
        {
            Handle trace = TR_TraceRayFilterEx(origin, targetOrigin, MASK_SOLID, RayType_EndPoint, FilterTarget, i);
        
            if ((TR_DidHit(trace) && TR_GetEntityIndex(trace) == i) || (GetVectorDistance(origin, targetOrigin) <= 100.0))
            {
                Freeze(i, client, f_smoke_freeze_duration);
                CloseHandle(trace);
            }
                
            else
            {
                CloseHandle(trace);
                
                GetClientEyePosition(i, targetOrigin);
                targetOrigin[2] -= 2.0;
        
                trace = TR_TraceRayFilterEx(origin, targetOrigin, MASK_SOLID, RayType_EndPoint, FilterTarget, i);
            
                if ((TR_DidHit(trace) && TR_GetEntityIndex(trace) == i) || (GetVectorDistance(origin, targetOrigin) <= 100.0))
                {
                    Freeze(i, client, f_smoke_freeze_duration);
                }
                
                CloseHandle(trace);
            }
        }
    }
    
    TE_SetupBeamRingPoint(origin, 10.0, f_smoke_freeze_distance, g_beamsprite, g_halosprite, 1, 1, 0.2, 100.0, 1.0, FreezeColor, 0, 0);
    TE_SendToAll();
    LightCreate(SMOKE, origin);
}

public bool FilterTarget(int entity, int contentsMask, any data)
{
    return (data == entity);
}

bool Freeze(int client, int attacker, float &time)
{
    #pragma unused client, attacker, time

    float dummy_duration = time;
    
    if (h_freeze_timer[client] != INVALID_HANDLE)
    {
        KillTimer(h_freeze_timer[client]);
        h_freeze_timer[client] = INVALID_HANDLE;
    }

    SetEntityMoveType(client, MOVETYPE_NONE);
    
    float vec[3];
    GetClientEyePosition(client, vec);
    vec[2] -= 50.0;
    //EmitAmbientSound(SOUND_FREEZE, vec, client, SNDLEVEL_RAIDSIREN);
    EmitSoundToAll(SOUND_FREEZE, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, vec);

    TE_SetupGlowSprite(vec, GlowSprite, dummy_duration, 2.0, 50);
    TE_SendToAll();
    
    h_freeze_timer[client] = CreateTimer(dummy_duration, Unfreeze, client, TIMER_FLAG_NO_MAPCHANGE);
    
    return true;
}

public Action Unfreeze(Handle timer, any client)
{
    if (h_freeze_timer[client] != INVALID_HANDLE)
    {
        SetEntityMoveType(client, MOVETYPE_WALK);
        h_freeze_timer[client] = INVALID_HANDLE;
    }
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if(StrContains(classname, "_projectile") != -1)
        SDKHook(entity, SDKHook_SpawnPost, Grenade_SpawnPost);
}

public void Grenade_SpawnPost(int entity)
{
    int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (client == -1) return;
    
    if (!b_enable)
    {
        return;
    }
    
    char classname[64];
    GetEdictClassname(entity, classname, 64);
    
    if (!strcmp(classname, "flashbang_projectile"))
    {
        // BeamFollowCreate(entity, FlashColor);
    } 
    else if (!strcmp(classname, "smokegrenade_projectile") || !strcmp(classname, "decoy_projectile"))
    //else if (!strcmp(classname, "smokegrenade_projectile"))
    {
        if (b_smoke_freeze)
        {
            // BeamFollowCreate(entity, FreezeColor);
            CreateTimer(1.3, CreateEvent_SmokeDetonate, entity, TIMER_FLAG_NO_MAPCHANGE);
        }
        else
        {
            // BeamFollowCreate(entity, SmokeColor);
        }

        int iReference = EntIndexToEntRef(entity);
        CreateTimer(0.1, Timer_OnGrenadeCreated, iReference);
    }
}

public Action Timer_OnGrenadeCreated(Handle timer, any ref)
{
    int entity = EntRefToEntIndex(ref);
    if (entity != INVALID_ENT_REFERENCE)
    {
        SetEntProp(entity, Prop_Data, "m_nNextThinkTick", -1);
    }
}

public Action CreateEvent_SmokeDetonate(Handle timer, any entity)
{
    if (!IsValidEdict(entity))
    {
        return Plugin_Stop;
    }
    
    static char g_szClassname[64];
    GetEdictClassname(entity, g_szClassname, sizeof(g_szClassname));
    if (!strcmp(g_szClassname, "smokegrenade_projectile", false) || !strcmp(g_szClassname, "decoy_projectile", false))
    {
        float origin[3];
        GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);

        int client = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
        GranadaCongela(client, origin);

        AcceptEntityInput(entity, "kill");
    }
    
    return Plugin_Stop;
}

void BeamFollowCreate(int entity, int color[4])
{
    if (b_trails)
    {
        TE_SetupBeamFollow(entity, BeamSprite, 0, 1.0, 10.0, 10.0, 5, color);
        TE_SendToAll();    
    }
}

void LightCreate(int grenade, float pos[3])   
{  
    int iEntity = CreateEntityByName("light_dynamic");
    DispatchKeyValue(iEntity, "inner_cone", "0");
    DispatchKeyValue(iEntity, "cone", "80");
    DispatchKeyValue(iEntity, "brightness", "1");
    DispatchKeyValueFloat(iEntity, "spotlight_radius", 150.0);
    DispatchKeyValue(iEntity, "pitch", "90");
    DispatchKeyValue(iEntity, "style", "1");
    switch(grenade)
    {
        case SMOKE : 
        {
            DispatchKeyValue(iEntity, "_light", "75 75 255 255");
            DispatchKeyValueFloat(iEntity, "distance", f_smoke_freeze_distance);
            //EmitSoundToAll(SOUND_FREEZE_EXPLODE, iEntity, SNDCHAN_WEAPON);
            EmitSoundToAll(SOUND_FREEZE_EXPLODE, SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, pos);
            CreateTimer(0.2, Delete, iEntity, TIMER_FLAG_NO_MAPCHANGE);
        }
    }
    DispatchSpawn(iEntity);
    TeleportEntity(iEntity, pos, NULL_VECTOR, NULL_VECTOR);
    AcceptEntityInput(iEntity, "TurnOn");
}

public Action Delete(Handle timer, any entity)
{
    if (IsValidEdict(entity))
    {
        AcceptEntityInput(entity, "kill");
    }
}

public Action NormalSHookCB(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &client, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (b_smoke_freeze && !strcmp(sample, "^weapons/smokegrenade/sg_explode.wav"))
    {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}