//States
DepthStencilState FinDepthState
{
	DepthEnable = TRUE;//Still use depth so we dont have fins coming through the model or through objects in front 
	DepthWriteMask = ZERO;//No depth mask to avoud opacity artifacts
};

DepthStencilState EnabledDepth
{
	DepthEnable = TRUE;
    DepthWriteMask = ALL;
};

SamplerState TexSampler
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Wrap; // or Mirror or Clamp or Border
    AddressV = Wrap; // or Mirror or Clamp or Border
};

RasterizerState NoCulling
{
	CullMode = NONE;
};

RasterizerState BackfaceCulling
{
	CullMode = FRONT;
};

BlendState EnableBlending
{
	BlendEnable[0] = TRUE;
	SrcBlend = SRC_ALPHA;
    DestBlend = INV_SRC_ALPHA;
};



//**********
// STRUCTS *
//**********
struct VS_DATA
{
	float3 Position : POSITION;
	float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD;
};

struct GS_DATA
{
	float4 Position : SV_POSITION;
	float3 Normal : NORMAL;
	float2 TexCoord : TEXCOORD0;
	int  LayerNr : TEXCOORD1;
};

//****************
// VERTEX SHADERS *
//****************
GS_DATA BaseVS(VS_DATA input)
{
	GS_DATA output = (GS_DATA)0;
	//Transform position to WorldViewProjection space keeping in mind float3 -> float4
	output.Position = mul(float4(input.Position,1.0f),gWorldViewProj);
	//Transform the normal to world space but do not rotate so cast Gworld to float3
	output.Normal = mul(input.Normal,(float3x3)gWorld);
	output.TexCoord = input.TexCoord;
	
	return output;
}

VS_DATA FurVS(VS_DATA input)
{
	return input;
}

//******************
// GEOMETRY SHADERS *
//******************
void CreateVertex(inout TriangleStream<GS_DATA> triStream, float3 pos, float3 normal, float2 texCoord,int layer)
{
	GS_DATA vertex = (GS_DATA)0;
	//Do the same as we would normally do in the vertex shader
	//Calculate the worldviewtransform for the new vertex taking into account float3 * float4
	vertex.Position = mul(float4(pos,1),gWorldViewProj);
	
	//Rotate the vertex normal without transforming it-> cast the gWorld to a float3x3
	vertex.Normal = mul(normal,(float3x3)gWorld);
	vertex.TexCoord = texCoord;//Pass the texture coords again
	vertex.LayerNr = layer;//Pass the layer the vertex resides on
	
	
	triStream.Append(vertex);
}

[maxvertexcount (34 * 3)]
void ShellGS(triangle VS_DATA vertices[3], inout TriangleStream<GS_DATA> triStream)
{
	//Get the three vertices
	VS_DATA vert1 = vertices[0];
	VS_DATA vert2 = vertices[1];
	VS_DATA vert3 = vertices[2];
	
	//Transform our normals to world space
	vert1.Normal = mul(vert1.Normal,(float3x3)gWorld);
	vert2.Normal = mul(vert2.Normal,(float3x3)gWorld);
	vert3.Normal = mul(vert3.Normal,(float3x3)gWorld);
	//Calculate the offset between 2 subsequent shell layers
	float offset = (gFurLength / ((float)gAmtOfLayers)) * 0.005f;
	//If we use heightmap we get random furlength values from a texture
	float height;
	if(gUseHeightMap){
	height = gHeightMap.SampleLevel(TexSampler,vert1.TexCoord,0).r;
	height = 1 - height;
	}
	else //Use uniform length
	{
		height = 1.0f;
	}
	
	[loop]
	for(int i = 0;i < gAmtOfLayers;++i)
	{	
		//Calculate the new layer vertice position for every of the three verts of the triangle
		vert1.Position = vert1.Position + (vert1.Normal * offset * height);
		vert2.Position = vert2.Position + (vert2.Normal * offset * height);
		vert3.Position = vert3.Position + (vert3.Normal * offset * height);
		
		
		//Create the vertex with a specially defined function
		CreateVertex(triStream,vert1.Position,vert1.Normal,vert1.TexCoord  ,i + 1);
		CreateVertex(triStream,vert2.Position ,vert2.Normal,vert2.TexCoord ,i + 1);
		CreateVertex(triStream,vert3.Position ,vert3.Normal,vert3.TexCoord ,i + 1);
		//Restart the trianglestream so we can go to the next triangle
		triStream.RestartStrip();
	}
	
}

[maxvertexcount(4)]
void FinGS(line VS_DATA lineInput[2], inout TriangleStream<GS_DATA> triStream)
{
	//calculate the midpoint which we will use to calculate the viewDirection
	float3 midPoint = (lineInput[0].Position + lineInput[1].Position) / 2.0f;
	//Calculate the average normal of the edge which we use to calculate a dotproduct between viewDir and the normal
	float3 averageNormal = (lineInput[0].Position + lineInput[1].Normal) / 2.0f;
	//Calculate the viewdrection
	float3 viewDir = midPoint - gViewInverse[3].xyz;
	viewDir = normalize(viewDir);
	
	//Calc a dotproduct between avg Normal of the line and the viewdir
	float dp = dot(averageNormal,-viewDir);
	//Set a value for which to compare dp with and see if its a silhouette edge
	float silhouetteDp = 0.1f;
	//Check if the dp is > than the threshold-> no silhouette edge so do not render
	if(dp > silhouetteDp)return;
	
	//Offset we will use to shrink the fins if we use the different height sizes of the shells just to make sure the fins dont stick out too much
	float offset = 1.0f;
	if(gUseHeightMap) offset = 0.8f;
	//Bottom 2
	CreateVertex(triStream,lineInput[0].Position,lineInput[0].Normal,float2(0,1),0);
	CreateVertex(triStream,lineInput[1].Position,lineInput[1].Normal,float2(1,1),0);
	//Top 2
	CreateVertex(triStream,lineInput[0].Position + (lineInput[0].Normal * gFurLength * offset )* 0.005,lineInput[0].Normal,float2(0,0),0);
	CreateVertex(triStream,lineInput[1].Position + (lineInput[1].Normal * gFurLength * offset )* 0.005,lineInput[1].Normal,float2(1,0),0);
	//Start new fin/quad 
	triStream.RestartStrip();
}

//***************
// PIXEL SHADERS *
//***************
float4 BasePS(GS_DATA input) : SV_TARGET 
{
	float3 diffuseColor = gDiffuseMap.Sample(TexSampler,input.TexCoord * gUVScale);
	
	//Diffuse Logic -> Lambert for better effect imho
	//...
	float diffuseValue = dot(-input.Normal,gLightDir);
	diffuseValue = saturate(diffuseValue);
	float halfLambert = pow((diffuseValue * 0.5 + 0.5),2.0f);
	diffuseColor *= halfLambert;

	
	diffuseColor *= gShadow;

	return float4(diffuseColor,1.0f);
	
}

float4 ShellPS(GS_DATA input) : SV_TARGET
{
	//If we dont want to render shells we just pass a color with zero opacity
	if(!gRenderShells)
	{
		return float4(0.0f,0.0f,0.0f,0.0f);
	}
	float4 diffuseColor = gDiffuseMap.Sample(TexSampler,input.TexCoord * gUVScale);
	float diffuseValue = dot(-input.Normal,gLightDir);
	diffuseValue = saturate(diffuseValue);
	float halfLambert = pow((diffuseValue * 0.5 + 0.5),2.0f);
	diffuseColor *= halfLambert;
	
	float4 opacity = gShellMap.Sample(TexSampler,input.TexCoord * gDensity * 0.05);
	diffuseColor.a = opacity.r * (1.0f - (float)input.LayerNr / gAmtOfLayers);
	
	
	if(diffuseColor.a <= gOpacityThreshold)
	{
		discard;
	}
	
	//Extra shadow effect ->Hugher value less shadow
	diffuseColor.rgb *= gShadow;
	
	return diffuseColor;
	
}

float4 FinPS(GS_DATA input) : SV_TARGET
{
	 if (!gRenderFins)
        return float4(0, 0, 0, 0);
		
    float4 color = gDiffuseMap.Sample(TexSampler,input.TexCoord * gDensity);
	
	float diffuseValue = dot(-input.Normal,gLightDir);
	diffuseValue = saturate(diffuseValue);
	float halfLambert = pow((diffuseValue * 0.5 + 0.5),2.0f);
	color *= halfLambert;
	
	color.rgb *= gShadow;
    float4 furAlpha = gFinsMap.Sample(TexSampler, input.TexCoord).r;
    color.a = furAlpha.r ;
    
	if(color.a <= gOpacityThreshold)discard;
	
	
    return color;

}


//*************
// TECHNIQUES *
//*************
technique10 FurRendering 
{
	pass basemodel 
	{
		SetRasterizerState(BackfaceCulling);
		
		SetVertexShader(CompileShader(vs_4_0, BaseVS()));
		SetPixelShader(CompileShader(ps_4_0, BasePS()));
	}
	
	pass fin
	{
		SetRasterizerState(NoCulling);
		
		SetDepthStencilState(FinDepthState,0);
		SetBlendState(EnableBlending,float4(0.0f,0.0f,0.0f,0.0f),0xFFFFFFFF);
		
		SetVertexShader(CompileShader(vs_4_0, FurVS()));
		SetGeometryShader(CompileShader(gs_4_0, FinGS()));
		SetPixelShader(CompileShader(ps_4_0, FinPS()));
	}
	
	pass shells{
		SetRasterizerState(NoCulling);
		
		SetDepthStencilState(EnabledDepth, 0);
		
		SetBlendState(EnableBlending,float4(0.0f,0.0f,0.0f,0.0f),0xFFFFFFFF);
		
		SetVertexShader(CompileShader(vs_4_0, FurVS()));
		SetGeometryShader(CompileShader(gs_4_0, ShellGS()));
		SetPixelShader(CompileShader(ps_4_0, ShellPS()));
	}
}