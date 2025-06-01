Includes = {
	"cw/lighting_util.fxh"
	"cw/lighting.fxh"
	"cw/shadow.fxh"
	"jomini/jomini.fxh"
	"constants.fxh"
	"cw/random.fxh"
}

PixelShader = 
{
	Code
	[[
		float4 cotc_GetHighlightColor( in float2 WorldSpacePosXZ )
		{
			float4 HighlightColor = BilinearColorSampleAtOffset( WorldSpacePosXZ, IndirectionMapSize, InvIndirectionMapSize, ProvinceColorIndirectionTexture, ProvinceColorTexture, HighlightProvinceColorsOffset );

			float3 Saturated = vec3( ( HighlightColor.r + HighlightColor.g + HighlightColor.b ) * 2 );
			HighlightColor.rgb = lerp( HighlightColor.rgb, Saturated, 0.1 );

			return HighlightColor;
		}

		void cotc_ApplyHighlightColor( inout float3 Diffuse, in float2 WorldSpacePosXZ )
		{
			float4 HighlightColor = cotc_GetHighlightColor( WorldSpacePosXZ );
			Diffuse = lerp( Diffuse, HighlightColor.rgb, saturate( HighlightColor.a * 1.0 * MapHighlightIntensity * 2.0 ) );
		}

		void cotc_CalculateLightingFromLight( SMaterialProperties MaterialProps, float3 ToCameraDir, float3 ToLightDir, float3 LightIntensity, float ShadowStrength, out float3 DiffuseOut, out float3 SpecularOut )
		{
			float3 H = normalize( ToCameraDir + ToLightDir );
			float NdotV = saturate( dot( MaterialProps._Normal, ToCameraDir ) ) + 1e-5;
			float NdotL = lerp(saturate( dot( MaterialProps._Normal, ToLightDir ) ) + 1e-5, 1.0, ShadowStrength);
			float NdotH = saturate( dot( MaterialProps._Normal, H ) );
			float LdotH = saturate( dot( ToLightDir, H ) );
			
			float DiffuseBRDF = CalcDiffuseBRDF( NdotV, NdotL, LdotH, MaterialProps._PerceptualRoughness );
			DiffuseOut = DiffuseBRDF * MaterialProps._DiffuseColor * LightIntensity; // * NdotL No Shadows
				
			#ifdef PDX_HACK_ToSpecularLightDir
				float3 H_Spec = normalize( ToCameraDir + PDX_HACK_ToSpecularLightDir );
				float NdotL_Spec = saturate( dot( MaterialProps._Normal, PDX_HACK_ToSpecularLightDir ) ) + 1e-5;
				float NdotH_Spec = saturate( dot( MaterialProps._Normal, H_Spec ) );
				float LdotH_Spec = saturate( dot( PDX_HACK_ToSpecularLightDir, H_Spec ) );
				float3 SpecularBRDF = CalcSpecularBRDF( MaterialProps._SpecularColor, LdotH_Spec, NdotH_Spec, NdotL_Spec, NdotV, MaterialProps._Roughness );
				SpecularOut = SpecularBRDF * LightIntensity * NdotL;
			#else
				float3 SpecularBRDF = CalcSpecularBRDF( MaterialProps._SpecularColor, LdotH, NdotH, NdotL, NdotV, MaterialProps._Roughness );
				SpecularOut = SpecularBRDF * LightIntensity * NdotL;
			#endif
		}
		
		void cotc_CalculateLightingFromLight( SMaterialProperties MaterialProps, SLightingProperties LightingProps, float ShadowStrength, out float3 DiffuseOut, out float3 SpecularOut )
		{
			cotc_CalculateLightingFromLight( MaterialProps, LightingProps._ToCameraDir, LightingProps._ToLightDir, LightingProps._LightIntensity * LightingProps._ShadowTerm, ShadowStrength, DiffuseOut, SpecularOut );
		}

		// Generate the texture co-ordinates for a PCF kernel
		void cotc_CalculateCoordinates( float2 ShadowCoord, inout float2 TexCoords[5] )
		{
			// Generate the texture co-ordinates for the specified depth-map size
			TexCoords[0] = ShadowCoord + float2( -KernelScale, 0.0f );
			TexCoords[1] = ShadowCoord + float2( 0.0f, KernelScale );
			TexCoords[2] = ShadowCoord + float2( KernelScale, 0.0f );
			TexCoords[3] = ShadowCoord + float2( 0.0f, -KernelScale );
			TexCoords[4] = ShadowCoord;
		}
		
		float cotc_CalculateShadow( float4 ShadowProj, PdxTextureSampler2D ShadowMap )
		{
			ShadowProj.xyz = ShadowProj.xyz / ShadowProj.w;
			
			float2 TexCoords[5];
			cotc_CalculateCoordinates( ShadowProj.xy, TexCoords );
			
			// Sample each of them checking whether the pixel under test is shadowed or not
			float fShadowTerm = 0.0f;
			for( int i = 0; i < 5; i++ )
			{				
				float A = PdxTex2DLod0( ShadowMap, TexCoords[i] ).r;
				float B = ShadowProj.z - Bias;
				
				// Texel is shadowed
				fShadowTerm += ( A < 0.99f && A < B ) ? 0.0 : 1.0;
			}
			
			// Get the average
			fShadowTerm = fShadowTerm / 5.0f;
			return lerp( 1.0, fShadowTerm, ShadowFadeFactor );
		}
		
		float2 cotc_RotateDisc( float2 Disc, float2 Rotate )
		{
			return float2( Disc.x * Rotate.x - Disc.y * Rotate.y, Disc.x * Rotate.y + Disc.y * Rotate.x );
		}
		
		float cotc_CalculateShadow( float4 ShadowProj, PdxTextureSampler2DCmp ShadowMap )
		{
			ShadowProj.xyz = ShadowProj.xyz / ShadowProj.w;

			float RandomAngle = CalcRandom( round( ShadowScreenSpaceScale * ShadowProj.xy ) ) * 3.14159 * 2.0;
			float2 Rotate = float2( cos( RandomAngle ), sin( RandomAngle ) );

			// Sample each of them checking whether the pixel under test is shadowed or not
			float ShadowTerm = 0.0;
			for( int i = 0; i < NumSamples; i++ )
			{
				float4 Samples = DiscSamples[i] * KernelScale;
				ShadowTerm += PdxTex2DCmpLod0( ShadowMap, ShadowProj.xy + cotc_RotateDisc( Samples.xy, Rotate ), ShadowProj.z - Bias );
				ShadowTerm += PdxTex2DCmpLod0( ShadowMap, ShadowProj.xy + cotc_RotateDisc( Samples.zw, Rotate ), ShadowProj.z - Bias );
			}

			// Get the average
			ShadowTerm *= 0.5; // We have 2 samples per "sample"
			ShadowTerm = ShadowTerm / float(NumSamples);
			
			float3 FadeFactor = saturate( float3( 1.0 - abs( 0.5 - ShadowProj.xy ) * 2.0, 1.0 - ShadowProj.z ) * 32.0 ); // 32 is just a random strength on the fade
			ShadowTerm = lerp( 1.0, ShadowTerm, min( min( FadeFactor.x, FadeFactor.y ), FadeFactor.z ) );

			return lerp( 1.0, ShadowTerm, ShadowFadeFactor );
		}

		float3 cotc_CalculateSunLighting( SMaterialProperties MaterialProps, SLightingProperties LightingProps, PdxTextureSamplerCube EnvironmentMap, float ShadowStrength )
		{
			SLightingProperties LightingPropsNoShadow = LightingProps;
			LightingPropsNoShadow._ShadowTerm = 1.0;

			float3 DiffuseLight;
			float3 SpecularLight;
			cotc_CalculateLightingFromLight( MaterialProps, LightingProps, ShadowStrength, DiffuseLight, SpecularLight );
			
			float3 DiffuseIBL;
			float3 SpecularIBL;
			CalculateLightingFromIBL( MaterialProps, LightingProps, EnvironmentMap, DiffuseIBL, SpecularIBL );
			
			return DiffuseLight + SpecularLight + DiffuseIBL + SpecularIBL;
		}

		SLightingProperties cotc_GetSunLightingProperties( float3 WorldSpacePos, float ShadowTerm )
		{
			SLightingProperties LightingProps;
			LightingProps._ToCameraDir = normalize( CameraPosition - WorldSpacePos );
			LightingProps._ToLightDir = ToSunDir;
			LightingProps._LightIntensity = SunDiffuse * SunIntensity;
			LightingProps._ShadowTerm = ShadowTerm;
			LightingProps._CubemapIntensity = CubemapIntensity;
			LightingProps._CubemapYRotation = CubemapYRotation;
			
			return LightingProps;
		}
		
		SLightingProperties cotc_GetSunLightingProperties( float3 WorldSpacePos, PdxTextureSampler2DCmp ShadowMap )
		{
			float4 ShadowProj = mul( ShadowMapTextureMatrix, float4( WorldSpacePos, 1.0 ) );
			float ShadowTerm = cotc_CalculateShadow( ShadowProj, ShadowMap );
			
			return cotc_GetSunLightingProperties( WorldSpacePos, ShadowTerm );
		}
	]]
}
