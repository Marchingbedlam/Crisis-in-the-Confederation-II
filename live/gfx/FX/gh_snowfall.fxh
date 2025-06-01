Includes = {
	"cw/camera.fxh"
	"cw/pdxterrain.fxh"
	"dynamic_masks.fxh"
	#"gh_utils.fxh"
}

PixelShader = {
	TextureSampler GH_SnowfallLayer
	{
		Index = 39
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		File = "gfx/map/environment/gh_snow_layer_1.dds"
		srgb = yes
	}

	Code [[
		//
		// Config
		//

		static const float3 GH_SNOWFALL_SNOW_COLOR = float3(0.4f, 0.6f, 1.0f);

		static const float GH_SNOWFALL_MAX_CAMERA_PITCH_COS  = 1.0f;
		static const float GH_SNOWFALL_FULL_CAMERA_PITCH_COS = 0.9f;

		static const float GH_SNOWFALL_CEILING_Y = 10.0f;
		static const float GH_SNOWFALL_FLOOR_Y   = -50.0f;

		static const float GH_SNOWFALL_SOFT_CEILING_Y = 1.0f;
		static const float GH_SNOWFALL_SOFT_FLOOR_Y   = -25.0f;

		static const float  GH_SNOWFALL_VERTICAL_SPEED = 0.2f;
		static const float2 GH_SNOWFALL_WIND_VELOCITY  = float2(-0.2f, -0.2f);

		static const float GH_SNOWFALL_LAYER_TILE_SIZE = 200.0f;
		static const float GH_SNOWFALL_LAYER_TILE_SIZE_SMALL = 100.0f;
		static const float GH_SNOWFALL_LAYER_TILE_SIZE_Y = 200.0f;

		static const int GH_SNOWFALL_LAYERS_COUNT = 5;

		static const float2 GH_SNOWFALL_LAYER_UV_OFFSET_STEP = float2(0.35f, -0.15f);

		//
		// Constants
		//

		static const float GH_SNOWFALL_VERTICAL_SPEED_MULTIPLIER = GH_SNOWFALL_VERTICAL_SPEED/(GH_SNOWFALL_CEILING_Y - GH_SNOWFALL_FLOOR_Y);

		static const float GH_SNOWFALL_LAYER_RELATIVE_TIME_SHIFT_STEP = 1.0f/float(GH_SNOWFALL_LAYERS_COUNT);

		//
		// Macros
		//

		// Extracted from gh_utils.fxh
		#ifndef PDX_OPENGL
			#define GH_UNROLL_EXACT(ITERATIONS_COUNT) [unroll(ITERATIONS_COUNT)]
		#else
			#define GH_UNROLL_EXACT(ITERATIONS_COUNT)
		#endif

		//
		// Service
		//

		float GH_GetCameraPitchCosSnow()
		{
			float3 CameraLookAtDirXZ = float3(CameraLookAtDir.x, 0.0f, CameraLookAtDir.z);

			return dot(CameraLookAtDir, CameraLookAtDirXZ);
		}

		//
		// Interface
		//

		float3 GH_ApplySnowfall(float3 Color, float3 WorldSpacePos)
		{
			float WinterSeverity = GetWinterSeverityValue(WorldSpacePos.xz*WorldSpaceToTerrain0To1);
			float CameraPitchCos = GH_GetCameraPitchCosSnow();

			float3 ToCameraNorm                   = normalize(CameraPosition - WorldSpacePos);
			float  CeilingParallaxDistance        = (GH_SNOWFALL_CEILING_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float  FloorParallaxDistance          = (GH_SNOWFALL_FLOOR_Y - WorldSpacePos.y)/ToCameraNorm.y;
			float2 CeilingParallaxWorldSpacePosXZ = (WorldSpacePos + CeilingParallaxDistance*ToCameraNorm).xz;
			float2 FloorParallaxWorldSpacePosXZ   = (WorldSpacePos + FloorParallaxDistance*ToCameraNorm).xz;

			float SnowAlpha = 0.0f;

			GH_UNROLL_EXACT(GH_SNOWFALL_LAYERS_COUNT)
			for (int i = 0; i < GH_SNOWFALL_LAYERS_COUNT; i++)
			{
				float  LayerRelativeHeight            = 1.0f - frac(GH_SNOWFALL_VERTICAL_SPEED_MULTIPLIER*GlobalTime + float(i)*GH_SNOWFALL_LAYER_RELATIVE_TIME_SHIFT_STEP);
				float2 CurrentParallaxWorldSpacePosXZ = lerp(FloorParallaxWorldSpacePosXZ, CeilingParallaxWorldSpacePosXZ, LayerRelativeHeight);

				CurrentParallaxWorldSpacePosXZ += GlobalTime*GH_SNOWFALL_WIND_VELOCITY;

				float LayerHeight                 = GH_SNOWFALL_FLOOR_Y + LayerRelativeHeight*(GH_SNOWFALL_CEILING_Y - GH_SNOWFALL_FLOOR_Y);
				float LayerAlphaFloorMultiplier   = smoothstep(GH_SNOWFALL_FLOOR_Y, GH_SNOWFALL_SOFT_FLOOR_Y, LayerHeight);
				float LayerAlphaCeilingMultiplier = smoothstep(GH_SNOWFALL_CEILING_Y, GH_SNOWFALL_SOFT_CEILING_Y, LayerHeight);
				float LayerAlphaMultiplier        = LayerAlphaFloorMultiplier*LayerAlphaCeilingMultiplier;

				float LayerSize = GH_SNOWFALL_LAYER_TILE_SIZE;
				if ( CameraPosition.y < GH_SNOWFALL_LAYER_TILE_SIZE_Y ) 
				{
					LayerSize = GH_SNOWFALL_LAYER_TILE_SIZE_SMALL;
				}
				float2 BaseLayerUV     = mod(CurrentParallaxWorldSpacePosXZ, LayerSize)/LayerSize;
				float2 AdjustedLayerUV = BaseLayerUV + float(i)*GH_SNOWFALL_LAYER_UV_OFFSET_STEP;

				SnowAlpha += LayerAlphaMultiplier*PdxTex2D(GH_SnowfallLayer, AdjustedLayerUV).a;
			}

			float CameraPitchAlphaMultiplier  = 1.0f - smoothstep(GH_SNOWFALL_FULL_CAMERA_PITCH_COS, GH_SNOWFALL_MAX_CAMERA_PITCH_COS, CameraPitchCos);

			SnowAlpha *= CameraPitchAlphaMultiplier;

			return lerp(Color, GH_SNOWFALL_SNOW_COLOR, saturate(SnowAlpha));
		}
	]]
}
