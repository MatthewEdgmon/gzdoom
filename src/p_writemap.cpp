#include "p_local.h"
#include "c_dispatch.h"
#include "gi.h"
#include "w_wad.h"
#include "r_defs.h"
#include "m_swap.h"

static int WriteTHINGS (FILE *file);
static int WriteLINEDEFS (FILE *file);
static int WriteSIDEDEFS (FILE *file);
static int WriteVERTEXES (FILE *file);
static int WriteSEGS (FILE *file);
static int WriteSSECTORS (FILE *file);
static int WriteNODES (FILE *file);
static int WriteSECTORS (FILE *file);
static int WriteREJECT (FILE *file);
static int WriteBLOCKMAP (FILE *file);
static int WriteBEHAVIOR (FILE *file);

#define APPEND(pos,name) \
	lumps[pos].FilePos = LittleLong(ftell (file)); \
	lumps[pos].Size = LittleLong(Write##name (file)); \
	memcpy (lumps[pos].Name, #name, sizeof(#name)-1);

CCMD (dumpmap)
{
	char *mapname;
	FILE *file;

	if (argv.argc() < 2)
	{
		Printf ("Usage: dumpmap <wadname> [mapname]\n");
		return;
	}

	if (argv.argc() < 3)
	{
		if (gameinfo.flags & GI_MAPxx)
		{
			mapname = "MAP01";
		}
		else
		{
			mapname = "E1M1";
		}
	}
	else
	{
		mapname = argv[2];
	}

	file = fopen (argv[1], "wb");
	if (file == NULL)
	{
		Printf ("Cannot write %s\n", argv[1]);
		return;
	}

	wadinfo_t header = { PWAD_ID, 12 };
	wadlump_t lumps[12] = { {0} };

	fseek (file, 12, SEEK_SET);
	
	lumps[0].FilePos = LittleLong(12);
	lumps[0].Size = 0;
	uppercopy (lumps[0].Name, mapname);

	APPEND(1, THINGS);
	APPEND(2, LINEDEFS);
	APPEND(3, SIDEDEFS);
	APPEND(4, VERTEXES);
	APPEND(5, SEGS);
	APPEND(6, SSECTORS);
	APPEND(7, NODES);
	APPEND(8, SECTORS);
	APPEND(9, REJECT);
	APPEND(10, BLOCKMAP);
	APPEND(11, BEHAVIOR);

	header.InfoTableOfs = ftell (file);

	fwrite (lumps, 16, 12, file);
	fseek (file, 0, SEEK_SET);
	fwrite (&header, 12, 1, file);

	fclose (file);
}

static int WriteTHINGS (FILE *file)
{
	mapthing2_t mt = { 0 };
	AActor *mo = players[consoleplayer].mo;

	mt.x = LittleShort(short(mo->x >> FRACBITS));
	mt.y = LittleShort(short(mo->y >> FRACBITS));
	mt.angle = LittleShort(short(MulScale32 (mo->angle >> ANGLETOFINESHIFT, 360)));
	mt.type = LittleShort(1);
	mt.flags = LittleShort(7|224|MTF_SINGLE);
	fwrite (&mt, sizeof(mt), 1, file);
	return sizeof (mt);
}

static int WriteLINEDEFS (FILE *file)
{
	maplinedef2_t mld;

	for (int i = 0; i < numlines; ++i)
	{
		mld.v1 = LittleShort(short(lines[i].v1 - vertexes));
		mld.v2 = LittleShort(short(lines[i].v2 - vertexes));
		mld.flags = LittleShort(short(lines[i].flags));
		mld.special = lines[i].special;
		for (int j = 0; j < 5; ++j)
		{
			mld.args[j] = (BYTE)lines[i].args[j];
		}
		mld.sidenum[0] = LittleShort(WORD(lines[i].sidenum[0]));
		mld.sidenum[1] = LittleShort(WORD(lines[i].sidenum[1]));
		fwrite (&mld, sizeof(mld), 1, file);
	}
	return numlines * sizeof(mld);
}

static const char *GetTextureName (int texnum)
{
	FTexture *tex = TexMan[texnum];

	if (tex != NULL)
	{
		return tex->Name;
	}
	else
	{
		return "-";
	}
}

static int WriteSIDEDEFS (FILE *file)
{
	mapsidedef_t msd;

	for (int i = 0; i < numsides; ++i)
	{
		msd.textureoffset = LittleShort(short(sides[i].textureoffset >> FRACBITS));
		msd.rowoffset = LittleShort(short(sides[i].rowoffset >> FRACBITS));
		msd.sector = LittleShort(short(sides[i].sector - sectors));
		uppercopy (msd.toptexture, GetTextureName (sides[i].toptexture));
		uppercopy (msd.bottomtexture, GetTextureName (sides[i].bottomtexture));
		uppercopy (msd.midtexture, GetTextureName (sides[i].midtexture));
		fwrite (&msd, sizeof(msd), 1, file);
	}
	return numsides * sizeof(msd);
}

static int WriteVERTEXES (FILE *file)
{
	mapvertex_t mv;

	for (int i = 0; i < numvertexes; ++i)
	{
		mv.x = LittleShort(short(vertexes[i].x >> FRACBITS));
		mv.y = LittleShort(short(vertexes[i].y >> FRACBITS));
		fwrite (&mv, sizeof(mv), 1, file);
	}
	return numvertexes * sizeof(mv);
}

static int WriteSEGS (FILE *file)
{
	mapseg_t ms;

	ms.offset = 0;		// unused by ZDoom, so just leave it 0
	for (int i = 0; i < numsegs; ++i)
	{
		if (segs[i].linedef!=NULL)
		{
			ms.v1 = LittleShort(short(segs[i].v1 - vertexes));
			ms.v2 = LittleShort(short(segs[i].v2 - vertexes));
			ms.linedef = LittleShort(short(segs[i].linedef - lines));
			ms.side = LittleShort(DWORD(segs[i].sidedef - sides) == segs[i].linedef->sidenum[0] ? 0 : 1);
			ms.angle = LittleShort(short(R_PointToAngle2 (segs[i].v1->x, segs[i].v1->y, segs[i].v2->x, segs[i].v2->y)>>16));
			fwrite (&ms, sizeof(ms), 1, file);
		}
	}
	return numsegs * sizeof(ms);
}

static int WriteSSECTORS (FILE *file)
{
	mapsubsector_t mss;

	for (int i = 0; i < numsubsectors; ++i)
	{
		mss.firstseg = LittleShort((WORD)subsectors[i].firstline);
		mss.numsegs = LittleShort((WORD)subsectors[i].numlines);
		fwrite (&mss, sizeof(mss), 1, file);
	}
	return numsubsectors * sizeof(mss);
}

static int WriteNODES (FILE *file)
{
	mapnode_t mn;

	for (int i = 0; i < numnodes; ++i)
	{
		mn.x = LittleShort(short(nodes[i].x >> FRACBITS));
		mn.y = LittleShort(short(nodes[i].y >> FRACBITS));
		mn.dx = LittleShort(short(nodes[i].dx >> FRACBITS));
		mn.dy = LittleShort(short(nodes[i].dy >> FRACBITS));
		for (int j = 0; j < 2; ++j)
		{
			for (int k = 0; k < 4; ++k)
			{
				mn.bbox[j][k] = LittleShort(short(nodes[i].bbox[j][k] >> FRACBITS));
			}
			WORD child;
			if ((size_t)nodes[i].children[j] & 1)
			{
				child = NF_SUBSECTOR | WORD((subsector_t *)((byte *)nodes[i].children[j] - 1) - subsectors);
			}
			else
			{
				child = WORD((node_t *)nodes[i].children[j] - nodes);
			}
			mn.children[j] = LittleShort(child);
		}
		fwrite (&mn, sizeof(mn), 1, file);
	}
	return numnodes * sizeof(mn);
}

static int WriteSECTORS (FILE *file)
{
	mapsector_t ms;

	for (int i = 0; i < numsectors; ++i)
	{
		ms.floorheight = LittleShort(short(sectors[i].floortexz >> FRACBITS));
		ms.ceilingheight = LittleShort(short(sectors[i].ceilingtexz >> FRACBITS));
		uppercopy (ms.floorpic, GetTextureName (sectors[i].floorpic));
		uppercopy (ms.ceilingpic, GetTextureName (sectors[i].ceilingpic));
		ms.lightlevel = LittleShort(sectors[i].lightlevel);
		ms.special = LittleShort(sectors[i].special);
		ms.tag = LittleShort(sectors[i].tag);
		fwrite (&ms, sizeof(ms), 1, file);
	}
	return numsectors * sizeof(ms);
}

static int WriteREJECT (FILE *file)
{
	return 0;
}

static int WriteBLOCKMAP (FILE *file)
{
	return 0;
}

static int WriteBEHAVIOR (FILE *file)
{
	static const BYTE dummy[16] = { 'A', 'C', 'S', 0, 8 };
	fwrite (dummy, 16, 1, file);
	return 16;
}
