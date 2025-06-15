Includes = {
	"gh_snowfall.fxh"
}

PixelShader = {
	Code [[
		void GH_ApplyAtmosphericEffects(inout float3 Color, inout float Alpha, float3 WorldSpacePos)
		{
			GH_ApplySnowfall(Color, Alpha, WorldSpacePos);
		}
	]]
}
