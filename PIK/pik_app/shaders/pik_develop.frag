// PIK — Shader de revelado (un solo pase, corre en la GPU vía FragmentProgram)
//
//   1. Corrección de color  -> LUT 3D guardado como strip 2D (N*N x N)
//   2. Halation             -> mapa de resplandor ya desenfocado (lo arma Dart)
//                              combinado con modo "screen"
//   3. Grano                -> ruido gaussiano con semilla por foto
//
// Orden de uniforms (setFloat usa estos índices):
//   0,1  uSize            tamaño de salida en px
//   2    uLutSize         N del cubo (33)
//   3    uHalationStrength
//   4    uGrainAmount     desviación estándar del grano (0..1)
//   5    uGrainSize       tamaño del "cristal" en px
//   6    uSeed            semilla (distinta por foto -> grano distinto)
//   7,8  uHalSize         tamaño en px del mapa de halation
// Samplers (setImageSampler): 0 uImage, 1 uLut, 2 uHalation

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uLutSize;
uniform float uHalationStrength;
uniform float uGrainAmount;
uniform float uGrainSize;
uniform float uSeed;
uniform vec2 uHalSize;

uniform sampler2D uImage;
uniform sampler2D uLut;
uniform sampler2D uHalation;

out vec4 fragColor;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// ------------------------------------------------------------ 1. LUT 3D
// Se lee siempre en el centro exacto del texel, así el resultado es el mismo
// con filtrado nearest o linear, y la interpolación trilineal la hacemos aquí.
vec3 lutTexel(float r, float g, float b) {
  float w = uLutSize * uLutSize;
  vec2 uv = vec2((b * uLutSize + r + 0.5) / w, (g + 0.5) / uLutSize);
  return texture(uLut, uv).rgb;
}

vec3 applyLut(vec3 c) {
  float n1 = uLutSize - 1.0;
  vec3 p = clamp(c, 0.0, 1.0) * n1;
  vec3 i0 = floor(p);
  vec3 i1 = min(i0 + 1.0, vec3(n1));
  vec3 f = p - i0;

  vec3 c00 = mix(lutTexel(i0.r, i0.g, i0.b), lutTexel(i1.r, i0.g, i0.b), f.r);
  vec3 c10 = mix(lutTexel(i0.r, i1.g, i0.b), lutTexel(i1.r, i1.g, i0.b), f.r);
  vec3 c01 = mix(lutTexel(i0.r, i0.g, i1.b), lutTexel(i1.r, i0.g, i1.b), f.r);
  vec3 c11 = mix(lutTexel(i0.r, i1.g, i1.b), lutTexel(i1.r, i1.g, i1.b), f.r);
  return mix(mix(c00, c10, f.g), mix(c01, c11, f.g), f.b);
}

// ------------------------------------------------------------ 2. Halation
// El mapa viene a 1/4 de resolución: lo ampliamos con bilineal manual.
vec3 halationAt(vec2 uv) {
  vec2 t = 1.0 / uHalSize;
  vec2 p = uv * uHalSize - 0.5;
  vec2 i = floor(p);
  vec2 f = p - i;
  vec2 lo = 0.5 * t;
  vec2 hi = 1.0 - 0.5 * t;
  vec3 a = texture(uHalation, clamp((i + vec2(0.5, 0.5)) * t, lo, hi)).rgb;
  vec3 b = texture(uHalation, clamp((i + vec2(1.5, 0.5)) * t, lo, hi)).rgb;
  vec3 c = texture(uHalation, clamp((i + vec2(0.5, 1.5)) * t, lo, hi)).rgb;
  vec3 d = texture(uHalation, clamp((i + vec2(1.5, 1.5)) * t, lo, hi)).rgb;
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ------------------------------------------------------------ 3. Grano
// Hash sin sin() (Dave Hoskins): estable en GPUs móviles.
float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

// Normal(0,1) por Box-Muller
float gauss(vec2 cell) {
  float u1 = max(hash12(cell + vec2(uSeed, uSeed * 1.7)), 1e-4);
  float u2 = hash12(cell + vec2(uSeed + 17.13, -uSeed * 0.9 + 3.71));
  return sqrt(-2.0 * log(u1)) * cos(6.2831853 * u2);
}

// Ruido gaussiano interpolado entre celdas de uGrainSize px -> "cristales" suaves
float grainNoise(vec2 px) {
  vec2 p = px / uGrainSize;
  vec2 i = floor(p);
  vec2 f = p - i;
  f = f * f * (3.0 - 2.0 * f);
  float a = gauss(i);
  float b = gauss(i + vec2(1.0, 0.0));
  float c = gauss(i + vec2(0.0, 1.0));
  float d = gauss(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  vec3 src = texture(uImage, uv).rgb;

  // 1. Color
  vec3 col = applyLut(src);

  // 2. Halation (screen: nunca oscurece, sólo agrega luz roja-naranja)
  vec3 h = clamp(halationAt(uv) * uHalationStrength, 0.0, 1.0);
  col = 1.0 - (1.0 - col) * (1.0 - h);

  // 3. Grano: más visible en medios tonos, menos en negros y blancos puros
  float L = dot(col, LUMA);
  float w = mix(0.35, 1.0, 4.0 * L * (1.0 - L));
  col += grainNoise(frag) * uGrainAmount * w;

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
