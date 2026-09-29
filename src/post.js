// Post-processing: the macro look. Depth of field focused on the cockroach
// (the world behind melts into bokeh), bloom on lights and highlights,
// then tone mapping, a vignette and a little film grain.
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { BokehPass } from 'three/addons/postprocessing/BokehPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';

const FinishShader = {
  uniforms: { tDiffuse: { value: null }, time: { value: 0 }, vignette: { value: 0.55 }, grain: { value: 0.035 } },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform float time; uniform float vignette; uniform float grain;
    varying vec2 vUv;
    float rand(vec2 c){ return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453); }
    void main(){
      vec4 c = texture2D(tDiffuse, vUv);
      vec2 d = vUv - 0.5;
      c.rgb *= 1.0 - vignette * smoothstep(0.25, 0.85, length(d * vec2(1.1, 1.0)));
      c.rgb += (rand(vUv * 731.0 + time) - 0.5) * grain;
      gl_FragColor = c;
    }`,
};

export function buildPost(renderer, scene, camera, quality) {
  const composer = new EffectComposer(renderer);
  composer.addPass(new RenderPass(scene, camera));
  const bokeh = new BokehPass(scene, camera, { focus: 0.14, aperture: 0.012, maxblur: 0.012 });
  composer.addPass(bokeh);
  const size = renderer.getSize(new THREE.Vector2());
  const bloom = new UnrealBloomPass(size, 0.28, 0.4, 0.97);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());
  const finish = new ShaderPass(FinishShader);
  composer.addPass(finish);

  function setQuality(q) {
    bokeh.enabled = q !== 'low';
    bloom.enabled = q !== 'low';
  }
  setQuality(quality);

  return {
    composer,
    setQuality,
    setFocus(d) { bokeh.uniforms.focus.value = d; },
    setSize(w, h) { composer.setSize(w, h); },
    render(time) {
      finish.uniforms.time.value = time % 100;
      composer.render();
    },
  };
}
