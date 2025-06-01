Includes = {
	"gh_snowfall.fxh"
}

PixelShader = {
	Code [[
		float3 GH_ApplyAtmosphericEffects(float3 Color, float3 WorldSpacePos)
		{
			float3 OutputColor = Color;

			OutputColor = GH_ApplySnowfall(OutputColor, WorldSpacePos);

			return OutputColor;
		}
	]]
}
