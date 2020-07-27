#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <laper32>
#include <bhopstats>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
    name = "[HNS] Speed Control",
    author = "Kroytz",
    description = "",
    version = BHOPSTATS_VERSION,
    url = "https://github.com/Kroytz"
}

public void Bunnyhop_OnTouchGround(int client)
{
    float flSpeed = ToolsGetSpeed(client);
    float fVelocity[3]; GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);

    if (flSpeed >= 900.0)
    {
        fVelocity[0] *= 0.6;
        fVelocity[1] *= 0.6;
    }
    else if (flSpeed > 380.0)
    {
        fVelocity[0] *= 0.8;
        fVelocity[1] *= 0.8;
    }

    ToolsSetVelocity(client, fVelocity, true, false);
}