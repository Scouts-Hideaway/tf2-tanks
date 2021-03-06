/*****************************/
//Pragma
#pragma semicolon 1
#pragma newdecls required

/*****************************/
//Defines
#define PLUGIN_NAME "[TF2] Tanks"
#define PLUGIN_DESCRIPTION "A gamemode for Team Fortress 2 involving Soldiers in tanks."
#define PLUGIN_VERSION "1.0.2"

/*****************************/
//Includes
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf2items>

/*****************************/
//ConVars

ConVar convar_CameraSnap;
ConVar convar_LockCamera;

/*****************************/
//Globals

bool g_BetweenRounds;

Handle g_PlayTaunt;
int g_iOffsetDamage;

bool g_IsTank[MAXPLAYERS + 1];
bool g_Snap[MAXPLAYERS + 1] = {true, ...};
bool g_AllowStopTank[MAXPLAYERS + 1];

/*****************************/
//Plugin Info
public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = "Drixevel", 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = "https://drixevel.dev/"
};

public void OnPluginStart()
{
	convar_CameraSnap = CreateConVar("sm_tanks_camera_snap", "80.0", "Shat offset should the camera snap to when moving it?", FCVAR_NOTIFY, true, 0.0);
	convar_LockCamera = CreateConVar("sm_tanks_lock_camera", "0", "Should the cameras be locked to up and down?", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	HookEvent("player_spawn", Event_OnPlayerSpawn);
	HookEvent("player_changeclass", Event_OnPlayerSpawn);
	HookEvent("player_death", Event_OnPlayerDeath);
	HookEvent("teamplay_round_start", Event_OnRoundStart);
	HookEvent("teamplay_round_win", Event_OnRoundEnd);

	Handle conf = LoadGameConfigFile("tf2.tanks");
	
	if (conf != null)
	{
		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetFromConf(conf, SDKConf_Signature, "CTFPlayer::PlayTauntSceneFromItem");
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);

		if ((g_PlayTaunt = EndPrepSDKCall()) == null)
			LogError("Error while parsing 'tf2.tanks': Invalid Signatures");
		
		delete conf;
	}

	g_iOffsetDamage = FindSendPropInfo("CTFProjectile_Rocket", "m_iDeflected") + 4;
}

public void OnMapStart()
{
	g_BetweenRounds = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_IsTank[i] = false;
		g_Snap[i] = true;
	}

	PrecacheSound("mvm/giant_common/giant_common_explodes_01.wav");
	PrecacheSound("mvm/giant_common/giant_common_explodes_02.wav");
}

public void OnClientConnected(int client)
{
	g_IsTank[client] = false;
	g_Snap[client] = true;
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if (condition == TFCond_Taunting)
	{
		g_IsTank[client] = false;
		g_Snap[client] = true;
	}
}

public void Event_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	SetTankMode(client, true);
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	g_IsTank[client] = false;
	g_Snap[client] = true;

	float origin[3];
	GetClientAbsOrigin(client, origin);

	EmitSoundToAll(GetRandomInt(1, 2) == 1 ? "mvm/giant_common/giant_common_explodes_01.wav" : "mvm/giant_common/giant_common_explodes_02.wav", client);
	TF2_Particle("mvm_loot_explosion", origin, client);
	DamageRadiusWithFalloff(origin, 500.0, 100.0, 450.0, client, 0, DMG_BLAST);
}

public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_BetweenRounds = false;

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && IsPlayerAlive(i))
			SetTankMode(i, true);
}

public void Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_BetweenRounds = true;

	for (int i = 1; i <= MaxClients; i++)
	{
		g_IsTank[i] = false;
		g_Snap[i] = true;

		if (IsClientInGame(i) && IsPlayerAlive(i))
			TF2_RemoveCondition(i, TFCond_Taunting);
	}
}

void SetTankMode(int client, bool toggle)
{
	if (g_BetweenRounds || !IsPlayerAlive(client))
		return;
	
	if (toggle)
	{
		TF2_RemoveCondition(client, TFCond_Taunting);

		if (!IsPlayerAlive(client) || TF2_GetPlayerClass(client) != TFClass_Soldier)
		{
			float vecOrigin[3];
			GetClientAbsOrigin(client, vecOrigin);

			float vecAngles[3];
			GetClientAbsAngles(client, vecAngles);

			TF2_SetPlayerClass(client, TFClass_Soldier, false, true);
			TF2_RespawnPlayer(client);

			TeleportEntity(client, vecOrigin, vecAngles, NULL_VECTOR);
		}

		CreateTimer(0.2, Timer_ExecuteTaunt, GetClientUserId(client));
	}
	else
	{
		g_AllowStopTank[client] = true;
		ClientCommand(client, "stop_taunt");
	}
}

public Action Timer_ExecuteTaunt(Handle timer, any data)
{
	int client = GetClientOfUserId(data);

	Handle hItem = TF2Items_CreateItem(OVERRIDE_ALL|PRESERVE_ATTRIBUTES|FORCE_GENERATION);
	
	TF2Items_SetClassname(hItem, "tf_wearable_vm");
	TF2Items_SetQuality(hItem, 6);
	TF2Items_SetLevel(hItem, 1);
	TF2Items_SetNumAttributes(hItem, 0);
	TF2Items_SetItemIndex(hItem, 1196);
	
	int item = TF2Items_GiveNamedItem(client, hItem);
	delete hItem;
	
	Address pEconItemView = GetEntityAddress(item) + view_as<Address>(FindSendPropInfo("CTFWearable", "m_Item"));
	
	if (g_PlayTaunt != null)
		SDKCall(g_PlayTaunt, client, pEconItemView);
}

public Action OnClientCommand(int client, int args)
{
	char sCommand[64];
	GetCmdArg(0, sCommand, sizeof(sCommand));
	
	if (StrEqual(sCommand, "taunt", false))
		return Plugin_Stop;

	if (StrEqual(sCommand, "stop_taunt", false))
	{
		if (g_AllowStopTank[client])
		{
			g_AllowStopTank[client] = false;
			return Plugin_Continue;
		}
		
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

public void OnClientDisconnect_Post(int client)
{
	g_AllowStopTank[client] = false;
}

public void OnGameFrame()
{
	int entity = -1; int client; float vecVelocity[3];
	while ((entity = FindEntityByClassname(entity, "tf_projectile_rocket")) != -1)
	{
		if ((client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity")) > 0 && GetEntProp(client, Prop_Send, "m_iTauntItemDefIndex") == 1196)
		{
			GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vecVelocity);
			vecVelocity[2] -= 10.0;
			TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vecVelocity);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "instanced_scripted_scene", false))
		SDKHook(entity, SDKHook_SpawnPost, OnInstancedScriptedScene);
}

public void OnInstancedScriptedScene(int iEntity)
{
	char sSceneFile[PLATFORM_MAX_PATH];
	GetEntPropString(iEntity, Prop_Data, "m_iszSceneFile", sSceneFile, sizeof(sSceneFile));

	int iOwner = GetEntPropEnt(iEntity, Prop_Data, "m_hOwner");

	if (StrEqual(sSceneFile, "scenes\\player\\soldier\\low\\taunt_vehicle_tank.vcd"))
	{
		g_IsTank[iOwner] = true;
		return;
	}
	else if (StrEqual(sSceneFile, "scenes\\player\\soldier\\low\\taunt_vehicle_tank_end.vcd"))
	{
		g_IsTank[iOwner] = false;
		return;
	}
	else if (!StrEqual(sSceneFile, "scenes\\player\\soldier\\low\\taunt_vehicle_tank_fire.vcd"))
		return;

	int projectile = CreateEntityByName("tf_projectile_rocket");
	
	if (!IsValidEntity(projectile))
		return;

	SetEntPropEnt(projectile, Prop_Send, "m_hOwnerEntity", iOwner);
	SetEntProp(projectile, Prop_Send, "m_iTeamNum", GetClientTeam(iOwner));

	if (TF2_IsPlayerInCondition(iOwner, TFCond_Buffed) && HasEntProp(projectile, Prop_Send, "m_bCritical"))
		SetEntProp(projectile, Prop_Send, "m_bCritical", true);

	SetEntDataFloat(projectile, g_iOffsetDamage, 120.0, true);  

	float fPos[3];
	GetClientEyePosition(iOwner, fPos);

	float fAng[3];
	GetClientAbsAngles(iOwner, fAng);

	fPos[2] -= 25.0;

	float fParam = GetEntPropFloat(iOwner, Prop_Send, "m_flPoseParameter", 4);

	float fAim = (fParam-0.5) * 120.0;
	fAng[1] += fAim;

	float fProj[2];
	fProj[0] = Cosine(DegToRad(fAng[1]));
	fProj[1] = Sine(DegToRad(fAng[1]));

	float fVel[3];
	fVel[0] = 4000.0 * fProj[0];
	fVel[1] = 4000.0 * fProj[1];

	fPos[0] += 20.0 * fProj[0];
	fPos[1] += 20.0 * fProj[1];

	DispatchSpawn(projectile);
	TeleportEntity(projectile, fPos, fAng, fVel);
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &iImpulse, float fVel[3], float fAng[3], int &iWeapon, int& iSubType, int& iCmdNum, int& iTickCount, int& iSeed, int iMouse[2])
{
	if (!g_IsTank[iClient])
		return Plugin_Continue;

	float snap = convar_CameraSnap.FloatValue;

	if (snap > 0)
	{
		if (iButtons & IN_BACK)
			g_Snap[iClient] = true;
		else if (FloatAbs(float(iMouse[0])) > snap)
			g_Snap[iClient] = false;

		if (!g_Snap[iClient] && !convar_LockCamera.BoolValue)
			return Plugin_Changed;

		float fParam = GetEntPropFloat(iClient, Prop_Send, "m_flPoseParameter", 4);
		float fAim = (fParam - 0.5) * 120.0;

		float fAngDesired[3];
		GetClientEyeAngles(iClient, fAngDesired);

		fAngDesired[0] = ClampFloat(fAngDesired[0] + 0.1 * float(iMouse[1]), -90.0, 90.0);
		fAngDesired[1] = fAng[1] + fAim;

		TeleportEntity(iClient, NULL_VECTOR, fAngDesired, NULL_VECTOR);
	}

	return Plugin_Changed;
}

float ClampFloat(float fValue, float fMin, float fMax)
{
	if (fValue < fMin)
		fValue = fMin;
	else if (fValue > fMax)
		fValue = fMax;

	return fValue;
}

void TF2_Particle(char[] name, float origin[3], int entity = -1, float angles[3] = {0.0, 0.0, 0.0}, bool resetparticles = false)
{
	int tblidx = FindStringTable("ParticleEffectNames");

	char tmp[256];
	int stridx = INVALID_STRING_INDEX;

	for (int i = 0; i < GetStringTableNumStrings(tblidx); i++)
	{
		ReadStringTable(tblidx, i, tmp, sizeof(tmp));
		if (StrEqual(tmp, name, false))
		{
			stridx = i;
			break;
		}
	}

	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", origin[0]);
	TE_WriteFloat("m_vecOrigin[1]", origin[1]);
	TE_WriteFloat("m_vecOrigin[2]", origin[2]);
	TE_WriteVector("m_vecAngles", angles);
	TE_WriteNum("m_iParticleSystemIndex", stridx);
	TE_WriteNum("entindex", entity);
	TE_WriteNum("m_iAttachType", 5);
	TE_WriteNum("m_bResetParticles", resetparticles);
	TE_SendToAll();
}

void DamageRadiusWithFalloff(float origin[3], float distance = 500.0, float min_damage = 10.0, float max_damage = 50.0, int attacker = 0, int inflictor = 0, int damagetype = DMG_GENERIC, int weapon = -1, float damageforce[3] = NULL_VECTOR)
{
	if (distance <= 0.0)
		return;

	float vecOrigin[3]; float actualdistance; float tempdamage;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || (attacker > 0 && i == attacker))
			continue;

		GetClientAbsOrigin(i, vecOrigin);
		
		actualdistance = GetVectorDistance(origin, vecOrigin);
		if (actualdistance > distance)
			continue;
		
		tempdamage = max_damage - (actualdistance - 0.0) / (distance - 0.0) * (max_damage - min_damage);

		SDKHooks_TakeDamage(i, inflictor, attacker, tempdamage, damagetype, weapon, damageforce, origin);
	}
}