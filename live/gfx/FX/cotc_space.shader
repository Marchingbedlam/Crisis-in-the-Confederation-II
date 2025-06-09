Includes = {
	"cw/pdxmesh.fxh"
	"cw/utility.fxh"
	"cw/shadow.fxh"
	"cw/camera.fxh"
	"cw/heightmap.fxh"
	"cw/pdxterrain.fxh"
	"jomini/jomini_fog.fxh"
	"jomini/jomini_lighting.fxh"
	"jomini/jomini_fog_of_war.fxh"
	"jomini/jomini_water.fxh"
	"jomini/jomini_mapobject.fxh"
	"constants.fxh"
	"standardfuncsgfx.fxh"
	"lowspec.fxh"
	"dynamic_masks.fxh"
	"liquid.fxh"
	#MOD(CL)
	"jomini/jomini_province_overlays.fxh"
	"bordercolor.fxh"
	"cotc_overrides.fxh"
	"gh_atmospheric.fxh"
	#END MOD
}

PixelShader =
{
	TextureSampler DiffuseMap
	{
		Index = 0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler PropertiesMap
	{
		Index = 1
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}
	TextureSampler NormalMap
	{
		Index = 2
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
	}	

	TextureSampler AtmosphereMap
    {
		Index = 3
        MagFilter = "Linear"
        MinFilter = "Linear"
        MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
    }

	TextureSampler EnvironmentMap
	{
		Ref = JominiEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler ShadowTexture
	{
		Ref = PdxShadowmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		CompareFunction = less_equal
		SamplerType = "Compare"
	}

	TextureSampler COTC_Plane_Mask
	{
		Index = 40
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		File = "gfx/map/terrain/cotc_plane_mask.png"
		#srgb = yes
	}

	# MOD(map-skybox)
	TextureSampler SkyboxSample
	{
		Index = 4
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
		File = "gfx/map/environment/SkyBox.dds"
		srgb = yes
	}
	# END MOD
}

VertexStruct VS_OUTPUT
{
    float4 Position			: PDX_POSITION;
	float3 Normal			: TEXCOORD0;
	float3 Tangent			: TEXCOORD1;
	float3 Bitangent		: TEXCOORD2;
	float2 UV0				: TEXCOORD3;
	float2 UV1				: TEXCOORD4;
	float3 WorldSpacePos	: TEXCOORD5;
	uint InstanceIndex 	: TEXCOORD6;
};

VertexShader =
{
	Code
	[[
		VS_OUTPUT ConvertOutput( VS_OUTPUT_PDXMESH In )
		{
			VS_OUTPUT Out;
			
			Out.Position = In.Position;
			Out.Normal = In.Normal;
			Out.Tangent = In.Tangent;
			Out.Bitangent = In.Bitangent;
			Out.UV0 = In.UV0;
			Out.UV1 = In.UV1;
			Out.WorldSpacePos = In.WorldSpacePos;

			return Out;
		}
	]]
	
	MainCode COTC_VS_standard
	{
		Input = "VS_INPUT_PDXMESHSTANDARD"
		Output = "VS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT Out = ConvertOutput( PdxMeshVertexShaderStandard( Input ) );
				Out.InstanceIndex = Input.InstanceIndices.y;
				return Out;
			}
		]]
	}

	MainCode COTC_VS_mapobject
	{
		Input = "VS_INPUT_PDXMESH_MAPOBJECT"
		Output = "VS_OUTPUT"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT Out = ConvertOutput( PdxMeshVertexShader( PdxMeshConvertInput( Input ), 0/*Skinning data not supported*/, UnpackAndGetMapObjectWorldMatrix( Input.InstanceIndex24_Opacity8 ) ) );
				Out.InstanceIndex = Input.InstanceIndex24_Opacity8;
				return Out;
			}
		]]
	}
}

PixelShader =
{
	# MOD(map-skybox)
	MainCode SKYX_PS_sky
	{
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float3 FromCameraDir = normalize(Input.WorldSpacePos - CameraPosition);
				float4 CubemapSample = PdxTexCube(SkyboxSample, FromCameraDir);
				CubemapSample.rgb = GH_ApplyAtmosphericEffects( CubemapSample.rgb, Input.WorldSpacePos );
				return CubemapSample;
			}
		]]
	}
	# END MOD
	MainCode COTC_PS_plane
	{
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				float2 ColorMapCoords =  Input.WorldSpacePos.xz *  WorldSpaceToTerrain0To1;
				float ProvinceStrength = smoothstep( 50, 100, CameraPosition.y );

				float3 ProvinceOverlayColor;
				float PreLightingBlend;
				float PostLightingBlend;
				GetProvinceOverlayAndBlend( ColorMapCoords, ProvinceOverlayColor, PreLightingBlend, PostLightingBlend );
				float3 PlaneMask = PdxTex2DLod0( COTC_Plane_Mask, COTC_WorldSpacePosXZToMapUV( Input.WorldSpacePos.xz ) );

				float Alpha = lerp(PlaneMask.r, 0.0, 1.0 - ProvinceStrength);
				float3 Color;
				if( ProvinceOverlayColor.r > 0.0 )
				{
					Color = ProvinceOverlayColor;
				}
				else
				{
					Color = PlaneMask;
				}
				return float4( Color, Alpha );
			}
		]]
	}
	
	MainCode COTC_PS_standard
	{
		Input = "VS_OUTPUT"
		Output = "PDX_COLOR"
		Code
		[[
			#ifndef DIFFUSE_UV_SET
				#define DIFFUSE_UV_SET Input.UV0
			#endif
			
			#ifndef NORMAL_UV_SET
				#define NORMAL_UV_SET Input.UV0
			#endif
			
			#ifndef PROPERTIES_UV_SET
				#define PROPERTIES_UV_SET Input.UV0
			#endif
			
			PDX_MAIN
			{
				float4 Diffuse = PdxTex2D( DiffuseMap, DIFFUSE_UV_SET );
				
				float4 Properties = PdxTex2D( PropertiesMap, PROPERTIES_UV_SET );
				#if defined( LOW_SPEC_SHADERS )
					float3 Normal = Input.Normal;
				#else
					float3 NormalSample = UnpackRRxGNormal( PdxTex2D( NormalMap, NORMAL_UV_SET ) );
				
					float3x3 TBN = Create3x3( normalize( Input.Tangent ), normalize( Input.Bitangent ), normalize( Input.Normal ) );
					float3 Normal = normalize( mul( NormalSample, TBN ) );
				#endif
				
				float2 ColorMapCoords =  Input.WorldSpacePos.xz *  WorldSpaceToTerrain0To1;

				SMaterialProperties MaterialProps = GetMaterialProperties( Diffuse.rgb, Normal, Properties.a, Properties.g, Properties.b );
				SLightingProperties LightingProps = GetSunLightingProperties( Input.WorldSpacePos, ShadowTexture );
				
				float ProvinceStrength = smoothstep(50, 100, CameraPosition.y);
				float3 Color = cotc_CalculateSunLighting( MaterialProps, LightingProps, EnvironmentMap, ProvinceStrength );
				float Alpha = Diffuse.a;

				float3 ProvinceOverlayColor;
				float PreLightingBlend;
				float PostLightingBlend;
				GetProvinceOverlayAndBlend( ColorMapCoords, ProvinceOverlayColor, PreLightingBlend, PostLightingBlend );
				float3 ToCameraDir = normalize( Input.WorldSpacePos.xyz - CameraPosition );

				#if defined( COTC_OUTER_FRESNEL ) || defined( COTC_FAR_OUTER_FRESNEL ) || defined( COTC_INNER_FRESNEL )
					float4 AtmoColor = PdxTex2D( AtmosphereMap, DIFFUSE_UV_SET );

					// float InSun = lerp(saturate( dot( LightingProps._ToLightDir, Input.Normal ) ), 1.0, ProvinceStrength);

					// Exterior
					#if defined( COTC_OUTER_FRESNEL )
						float FresnelFactor = saturate( Fresnel( abs( dot( ToCameraDir, Input.Normal ) ), 0.0, 0.8) );
						Alpha = Alpha - FresnelFactor;
						Color = lerp( AtmoColor, ProvinceOverlayColor, ProvinceStrength );
					#endif

					// Interior
					#if defined( COTC_INNER_FRESNEL )
						float FresnelFactor = saturate( Fresnel( abs( dot( ToCameraDir, Input.Normal ) ), 0.1, 2.0 - (1.5 * ProvinceStrength) ) /** * InSun **/ );
						AtmoColor.rgb = lerp( AtmoColor, ProvinceOverlayColor, ProvinceStrength );
						Color = lerp( Color, AtmoColor, FresnelFactor );
					#endif
				#endif

				cotc_ApplyHighlightColor(Color, ColorMapCoords);

				return float4( Color, Alpha );
			}
		]]
	}
}

DepthStencilState DepthStencilState
{
	StencilEnable = yes
}

BlendState alpha_to_coverage
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
	AlphaToCoverage = yes
}

Effect cotc_planet
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_INNER_FRESNEL" "COTC_COLOR" }
	DepthStencilState = DepthStencilState
}	

Effect cotc_planet_city
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_INNER_FRESNEL" "COTC_NO_SHADOW" "COTC_COLOR" }
	DepthStencilState = DepthStencilState
}	

Effect cotc_planet_atmosphere
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_OUTER_FRESNEL" "COTC_NO_SHADOW" "COTC_COLOR" }
	DepthStencilState = DepthStencilState
}

Effect cotc_star
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	DepthStencilState = DepthStencilState
}	

Effect cotc_star_atmosphere
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_OUTER_FRESNEL" "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_standard
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_standard_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_standard_selection_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_standard"
	BlendState = "alpha_to_coverage"
	Defines = { "COTC_NO_SHADOW" }
	DepthStencilState = DepthStencilState
}

Effect cotc_plane
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "COTC_PS_plane"
	BlendState = "alpha_to_coverage"
	DepthStencilState = DepthStencilState
}

Effect cotc_plane_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_plane"
	BlendState = "alpha_to_coverage"
	DepthStencilState = DepthStencilState
}

Effect cotc_plane_selection_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "COTC_PS_plane"
	BlendState = "alpha_to_coverage"
	DepthStencilState = DepthStencilState
}

# MOD(map-skybox)
Effect SKYX_sky
{
	VertexShader = "COTC_VS_standard"
	PixelShader = "SKYX_PS_sky"
	DepthStencilState = DepthStencilState
}

Effect SKYX_sky_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "SKYX_PS_sky"
	DepthStencilState = DepthStencilState
}

Effect SKYX_sky_selection_mapobject
{
	VertexShader = "COTC_VS_mapobject"
	PixelShader = "SKYX_PS_sky"
	DepthStencilState = DepthStencilState
}
# END MOD
