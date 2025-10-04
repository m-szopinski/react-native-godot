import React, { useMemo, useState, useEffect, useRef } from 'react';
import { Platform, View, Text, NativeModules } from 'react-native';
import { WebView } from 'react-native-webview';

const INDEX_PATH = 'web-export/index.html';

// Opcjonalny fallback (tylko index.html) – generowany w CI (diagnostyka)
let fallbackIndexHtmlB64: string | undefined;
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  fallbackIndexHtmlB64 = require('./__generated__/godotIndexInline').godotIndexHtmlB64;
} catch {
  /* brak – ok */
}

export interface GodotViewProps {
  style?: any;
  onReady?: () => void;
  source?: any;
  debug?: boolean;
}

interface ConsoleEntry {
  level: 'log' | 'warn' | 'error';
  msg: string;
  t: number;
}

export const GodotView: React.FC<GodotViewProps> = ({ style, onReady, debug }) => {
  const platformMode = Platform.OS;
  const [loaded, setLoaded] = useState(false);
  const [consoleEntries, setConsoleEntries] = useState<ConsoleEntry[]>([]);
  const [canvasDetected, setCanvasDetected] = useState(false);
  const [threadWarning, setThreadWarning] = useState(false);
  const [whiteScreen, setWhiteScreen] = useState(false);
  const [glOk, setGlOk] = useState<boolean | null>(null);
  const [fetchErrors, setFetchErrors] = useState<string[]>([]);
  const [xhrErrors, setXhrErrors] = useState<string[]>([]);
  const [moduleSeen, setModuleSeen] = useState(false);
  const [scriptErrors, setScriptErrors] = useState<string[]>([]);
  const [wasmErrors, setWasmErrors] = useState<string[]>([]);
  const [reloadKey, setReloadKey] = useState(0);
  const [indexStatus, setIndexStatus] = useState<string | null>(null);
  const [scriptList, setScriptList] = useState<string[]>([]);
  const [bodyDumpInfo, setBodyDumpInfo] = useState<string | null>(null);
  const [errorHint, setErrorHint] = useState<string | null>(null);           // NEW
  const [initialHref, setInitialHref] = useState<string | null>(null);       // NEW
  const reloadTriedRef = useRef(false);
  const lastUriLogRef = useRef<string | null>(null);
  const startRef = useRef(Date.now());
  const effectiveDebug = debug ?? (Platform.OS !== 'web');

  const pushConsole = (level: ConsoleEntry['level'], msg: string) =>
    setConsoleEntries(prev => [...prev.slice(-199), { level, msg, t: Date.now() - startRef.current }]);

  useMemo(() => {
    console.log('[GodotView] Mount (platform=' + platformMode + ')');
  }, [platformMode]);

  useEffect(() => {
    // Dodatkowa heurystyka: jeśli moduł widziany, brak canvas/gl po 2500ms → biała plansza
    if (!moduleSeen) return;
    if (loaded && (canvasDetected || glOk)) return;
    const id = setTimeout(() => {
      if (!canvasDetected && glOk === null) {
        pushConsole('warn', 'Module seen but no canvas / GL context yet (threads? OffscreenCanvas? assets?).');
      }
    }, 2500);
    return () => clearTimeout(id);
  }, [moduleSeen, canvasDetected, glOk, loaded]);

  // Timeout diagnozy białego ekranu
  useEffect(() => {
    if (loaded && canvasDetected) return;
    const id = setTimeout(() => {
      if (!loaded || !canvasDetected) {
        setWhiteScreen(true);
        console.warn('[GodotView] Possible white screen (no canvas / not loaded in 2500ms).');
      }
    }, 2500);
    return () => clearTimeout(id);
  }, [loaded, canvasDetected]);

  // iOS: spróbuj wyliczyć absolutną ścieżkę bundle
  const iosFileUri = useMemo(() => {
    if (Platform.OS !== 'ios') return null;
    try {
      const scriptURL: string | undefined = NativeModules?.SourceCode?.scriptURL;
      if (!scriptURL) return null;
      // przykład: file:///var/containers/Bundle/Application/XXXX/APP.app/main.jsbundle
      const bundleBase = scriptURL.substring(0, scriptURL.lastIndexOf('/'));
      const candidate = bundleBase + '/' + INDEX_PATH;
      return candidate.startsWith('file://') ? candidate : 'file://' + candidate;
    } catch {
      return null;
    }
  }, []);

  const injectedBefore = `
    (function(){
      function post(o){
        try{ window.ReactNativeWebView.postMessage(JSON.stringify(o)); }catch(e){}
      }
      post({type:'initial_location', href: location.href}); // NEW

      // Console capture
      ['log','warn','error'].forEach(function(l){
        const orig = console[l];
        console[l] = function(){
          const msg = Array.prototype.slice.call(arguments).map(a=>{
            try { return (typeof a==='object')?JSON.stringify(a):String(a); } catch(e){ return String(a); }
          }).join(' ');
          post({type:'console', level:l, msg:msg});
          orig && orig.apply(console, arguments);
        };
      });

      // WebAssembly instrumentation
      (function(){
        var _origInst = WebAssembly.instantiate;
        var _origStream = WebAssembly.instantiateStreaming;
        WebAssembly.instantiate = function(bin, imp){
          try {
            return _origInst.call(WebAssembly, bin, imp).catch(function(e){
              post({type:'wasm_error', msg:''+e});
              throw e;
            });
          } catch(err){
            post({type:'wasm_error', msg:''+err});
            throw err;
          }
        };
        if (_origStream){
          WebAssembly.instantiateStreaming = function(respP, imp){
            try {
              return _origStream.call(WebAssembly, respP, imp).catch(function(e){
                post({type:'wasm_error', msg:''+e});
                throw e;
              });
            } catch(err){
              post({type:'wasm_error', msg:''+err});
              throw err;
            }
          };
        }
      })();

      // Global error & unhandled rejection
      window.addEventListener('error', function(e){
        post({type:'console', level:'error', msg:'Error: '+e.message});
      });
      window.addEventListener('unhandledrejection', function(e){
        post({type:'console', level:'error', msg:'UnhandledRejection: '+(e.reason&&e.reason.message||e.reason)});
      });

      // Detect Module (Godot/Emscripten) appearance
      var moduleInterval = setInterval(function(){
        if (window.Module) {
          post({type:'module_seen'});
          clearInterval(moduleInterval);
        }
      }, 100);

      // --- Track loaded <script src> sequence ---
      (function(){
        const origCreateEl = document.createElement;
        const scripts = [];
        document.createElement = function(){
          const el = origCreateEl.apply(document, arguments);
          try {
            if ((arguments[0]+'').toLowerCase()==='script') {
              el.addEventListener('load', function(){
                if (el.src) { scripts.push(el.src); post({type:'script_list', list:scripts.slice(-12)}); }
              });
              el.addEventListener('error', function(){
                post({type:'script_error', src: el.src || '(inline)'});
              });
            }
          } catch(_){}
          return el;
        };
      })();

      // --- Index fetch status (skip on file:// to avoid false errors) ---
      setTimeout(function(){
        try {
          var proto = location.protocol;
          if (proto === 'file:') {
            // Lokalny plik – fetch bywa blokowany / zwraca błąd -> pomijamy
            post({type:'index_fetch_skip'});
          } else {
            var base = (location.href.split('?')[0]||'');
            fetch(base).then(r=>{
              post({type:'index_fetch', status:r.status});
              if(r.status===200){
                return r.text();
              }
            }).then(txt=>{
              if(!txt) return;
              if(!document.querySelector('canvas')){
                post({type:'diag_dump', body_len: txt.length });
              }
            }).catch(e=>{
              // Spróbuj fallback: jeśli dokument już ma treść – oznacz jako fallback
              var bodyLen = (document.documentElement && document.documentElement.innerHTML||'').length;
              if (bodyLen > 50) {
                post({type:'index_fetch_fallback', body_len: bodyLen, err:''+e});
              } else {
                post({type:'index_fetch_error', err:''+e});
              }
            });
          }
        } catch(e){
          post({type:'index_fetch_error', err:''+e});
        }
      }, 200);

      // --- Delayed body / layout dump if still no canvas & no Module ---
      setTimeout(function(){
        try {
          if(!window.Module && !document.querySelector('canvas')){
            var htmlLen = (document.documentElement && document.documentElement.innerHTML||'').length;
            post({type:'diag_dump', body_len: htmlLen });
          }
        } catch(e){}
      }, 2400);

      // Patch document.createElement to detect early canvas creation
      const origCreate = document.createElement;
      document.createElement = (function(prev){
        return function(){
          const el = prev.apply(document, arguments);
          try {
            if ((arguments[0]+'').toLowerCase()==='canvas') {
              post({type:'canvas_created'});
            }
          } catch(_) {}
          return el;
        };
      })(document.createElement);

      // Patch getContext to detect GL success / fail
      const ctxTargets = ['webgl','webgl2','experimental-webgl'];
      const origGetContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function(type, attrs){
        let ctx;
        try {
          ctx = origGetContext.call(this, type, attrs);
        } catch(e) {
          post({type:'gl_context_fail', api:type, err:''+e});
          throw e;
        }
        if (ctx && ctxTargets.indexOf((type||'').toLowerCase())>=0){
          post({type:'gl_context_ok', api:type});
        } else if (!ctx && ctxTargets.indexOf((type||'').toLowerCase())>=0){
          post({type:'gl_context_fail', api:type, err:'null returned'});
        }
        return ctx;
      };

      // Instrument fetch
      const origFetch = window.fetch;
      window.fetch = function(resource, init){
        return origFetch(resource, init).then(function(r){
          try {
            if (!r.ok) {
              var url = (typeof resource==='string')?resource:(resource&&resource.url);
              post({type:'fetch_error', url:url, status:r.status});
            }
          } catch(_) {}
            return r;
        }).catch(function(err){
          try {
            var url = (typeof resource==='string')?resource:(resource&&resource.url);
            post({type:'fetch_error', url:url, status:-1, err:''+err});
          } catch(_) {}
          throw err;
        });
      };

      // Instrument XHR
      const OrigXHR = XMLHttpRequest;
      XMLHttpRequest = function(){
        const xhr = new OrigXHR();
        let _url = '';
        const origOpen = xhr.open;
        xhr.open = function(m,u){
          _url = u || '';
          return origOpen.apply(xhr, arguments);
        };
        xhr.addEventListener('load', function(){
          try {
            if (xhr.status && xhr.status !== 200) {
              post({type:'xhr_error', url:_url, status:xhr.status});
            }
          } catch(_){}
        });
        xhr.addEventListener('error', function(){
          post({type:'xhr_error', url:_url, status:-1});
        });
        return xhr;
      };

      // Canvas polling (fallback if we missed createElement)
      let checks = 0;
      const iv = setInterval(function(){
        const c = document.querySelector('canvas');
        if(c){
          post({type:'canvas_detected'});
          clearInterval(iv);
        } else {
          checks++;
          if(checks===10) {
            post({type:'console', level:'warn', msg:'No canvas after ~1s'});
          }
        }
      },100);

      // SharedArrayBuffer / threads heuristic
      setTimeout(function(){
        if (typeof SharedArrayBuffer === 'undefined') {
          post({type:'sabt_unavailable'});
        }
      }, 400);
    })();
    true;
  `;

  const onMessage = (e: any) => {
    let data = e?.nativeEvent?.data;
    if (!data) return;
    try { data = JSON.parse(data); } catch { /* ignore */ }
    if (!data || typeof data !== 'object') return;
    if (data.type === 'index_fetch') {
      setIndexStatus('HTTP ' + data.status);
      pushConsole(data.status === 200 ? 'log' : 'warn', 'Index fetch status: ' + data.status);
    } else if (data.type === 'index_fetch_skip') {
      setIndexStatus('SKIP(file://)');
      pushConsole('log', 'Index fetch skipped (file://)');
    } else if (data.type === 'index_fetch_fallback') {
      setIndexStatus('FALLBACK(body)');
      pushConsole('warn', 'Index fetch failed, using existing DOM (len=' + data.body_len + ') err=' + data.err);
    } else if (data.type === 'index_fetch_error') {
      setIndexStatus('ERR');
      pushConsole('error', 'Index fetch error: ' + data.err);
    } else if (data.type === 'script_list') {
      if (Array.isArray(data.list)) {
        setScriptList(data.list);
      }
    } else if (data.type === 'diag_dump') {
      if (data.body_len != null) {
        setBodyDumpInfo('body_len=' + data.body_len);
        pushConsole('log', 'Body dump info ' + data.body_len);
      }
    } else if (data.type === 'console') {
      pushConsole(data.level || 'log', data.msg || '');
    } else if (data.type === 'canvas_detected' || data.type === 'canvas_created') {
      setCanvasDetected(true);
      pushConsole('log', data.type === 'canvas_detected' ? 'Canvas detected (poll)' : 'Canvas created');
    } else if (data.type === 'gl_context_ok') {
      setGlOk(true);
      pushConsole('log', 'GL context ok (' + data.api + ')');
    } else if (data.type === 'gl_context_fail') {
      setGlOk(false);
      pushConsole('error', 'GL context fail (' + data.api + '): ' + (data.err||''));
    } else if (data.type === 'fetch_error') {
      const desc = (data.url||'?') + ' status=' + data.status + (data.err?(' err='+data.err):'');
      setFetchErrors(prev => [...prev.slice(-9), desc]);
      pushConsole('warn', 'Fetch error ' + desc);
    } else if (data.type === 'xhr_error') {
      const desc = (data.url||'?') + ' status=' + data.status;
      setXhrErrors(prev => [...prev.slice(-9), desc]);
      pushConsole('warn', 'XHR error ' + desc);
    } else if (data.type === 'sabt_unavailable') {
      setThreadWarning(true);
      pushConsole('warn', 'SharedArrayBuffer unavailable (threads?).');
    } else if (data.type === 'module_seen') {
      setModuleSeen(true);
      pushConsole('log', 'Module detected');
    } else if (data.type === 'script_error') {
      setScriptErrors(prev => [...prev.slice(-9), data.src || '(unknown script)']);
      pushConsole('error', 'Script load error: ' + (data.src || '(inline)'));
    } else if (data.type === 'script_stall') {
      pushConsole('warn', 'Scripts pending after 2s (count=' + data.count + ')');
    } else if (data.type === 'wasm_error') {
      setWasmErrors(prev => [...prev.slice(-9), data.msg || 'wasm error']);
      pushConsole('error', 'WASM error: ' + data.msg);
    } else if (data.type === 'initial_location') {
      setInitialHref(data.href || null);
    }
  };

  const Overlay = effectiveDebug ? (
    <View style={{
      position: 'absolute', top: 4, left: 4, right: 4,
      backgroundColor: 'rgba(0,0,0,0.7)',
      padding: 6, borderRadius: 6, maxHeight: '55%'
    }}>
      <Text style={{ color: '#9ef', fontSize: 11, fontWeight: '600' }}>
        GodotView Debug • {loaded ? 'LOADED' : 'LOADING'}
        {' • '}{canvasDetected ? 'CANVAS' : 'NO-CANVAS'}
        {' • GL:'}{glOk === null ? '?' : glOk ? 'OK' : 'FAIL'}
        {' • M:'}{moduleSeen ? 'Y' : 'N'}
        {indexStatus ? ' • IDX:'+indexStatus : ''}
        {' • '}{Math.round((Date.now()-startRef.current)/1000)}s
      </Text>
      {!!initialHref && (
        <Text style={{ color: '#8fd', fontSize: 10, marginTop: 2 }}>
          HREF: {initialHref}
        </Text>
      )}
      {!!scriptList.length && (
        <Text style={{ color: '#8fd', fontSize: 10, marginTop: 4 }}>
          Scripts ({scriptList.length}): {scriptList.map(s=>s.split('/').pop()).slice(-5).join(', ')}
        </Text>
      )}
      {bodyDumpInfo && (
        <Text style={{ color: '#bdf', fontSize: 10, marginTop: 2 }}>
          Body: {bodyDumpInfo}
        </Text>
      )}
      {whiteScreen && (
        <Text style={{ color: '#f88', fontSize: 11, marginTop: 4 }}>
          White screen heuristic – check threads / OffscreenCanvas / asset presence.
        </Text>
      )}
      {threadWarning && (
        <Text style={{ color: '#ffd27a', fontSize: 11, marginTop: 4 }}>
          SharedArrayBuffer not available – rebuild export without threads for iOS WKWebView.
        </Text>
      )}
      {glOk === false && (
        <Text style={{ color: '#ffb080', fontSize: 11, marginTop: 4 }}>
          WebGL context failed – possibly unsupported extensions or context attributes.
        </Text>
      )}
      {!!fetchErrors.length && (
        <View style={{ marginTop: 4 }}>
          <Text style={{ color: '#ffa', fontSize: 10 }}>Fetch errors:</Text>
          {fetchErrors.map((f,i)=><Text key={i} style={{ color:'#ffa', fontSize:10 }} numberOfLines={1}>{f}</Text>)}
        </View>
      )}
      {!!xhrErrors.length && (
        <View style={{ marginTop: 4 }}>
          <Text style={{ color: '#ffa', fontSize: 10 }}>XHR errors:</Text>
          {xhrErrors.map((f,i)=><Text key={i} style={{ color:'#ffa', fontSize:10 }} numberOfLines={1}>{f}</Text>)}
        </View>
      )}
      {!!scriptErrors.length && (
        <View style={{ marginTop: 4 }}>
          <Text style={{ color: '#ff9090', fontSize: 10 }}>Script errors:</Text>
          {scriptErrors.map((s,i)=><Text key={i} style={{ color:'#ff9090', fontSize:10 }} numberOfLines={1}>{s}</Text>)}
        </View>
      )}
      {!!wasmErrors.length && (
        <View style={{ marginTop: 4 }}>
          <Text style={{ color: '#ffbfbf', fontSize: 10 }}>WASM errors:</Text>
          {wasmErrors.map((w,i)=><Text key={i} style={{ color:'#ffbfbf', fontSize:10 }} numberOfLines={2}>{w}</Text>)}
        </View>
      )}
      {errorHint && (
        <View style={{ marginTop: 6 }}>
          <Text style={{ color: '#ffeb90', fontSize: 10, fontWeight: '600' }}>Hint:</Text>
          {errorHint.split('\n').map((l,i)=>
            <Text key={i} style={{ color:'#ffeb90', fontSize:10 }} numberOfLines={3}>{l}</Text>
          )}
        </View>
      )}
      <View style={{ marginTop: 4 }}>
        {consoleEntries.slice(-10).map((c, i) => (
          <Text
            key={i}
            style={{
              color: c.level === 'error' ? '#ff8080' : c.level === 'warn' ? '#ffd27a' : '#ddd',
              fontSize: 10
            }}
            numberOfLines={3}
          >
            [{c.t}ms][{c.level}] {c.msg}
          </Text>
        ))}
        {consoleEntries.length === 0 && (
          <Text style={{ color: '#aaa', fontSize: 10 }}>No console output yet…</Text>
        )}
      </View>
    </View>
  ) : null;

  // WEB
  if (Platform.OS === 'web') {
    console.log('[GodotView] Using iframe path=' + INDEX_PATH);
    return (
      <div style={{ width: '100%', height: '100%', position: 'relative', ...(style || {}) }}>
        <iframe
          src={INDEX_PATH}
          title="GodotWeb"
          style={{ border: 'none', width: '100%', height: '100%' }}
          onLoad={() => {
            console.log('[GodotView] onReady (web iframe)');
            setLoaded(true);
            onReady?.();
          }}
        />
        {Overlay}
      </div>
    );
  }

  // NATIVE
  // iOS: prefer absolutny file:// gdy dostępny
  const uri =
    Platform.OS === 'android'
      ? 'file:///android_asset/web-export/index.html'
      : (iosFileUri || INDEX_PATH);

  // finalUri z cache-bust po auto‑reload
  const finalUri = reloadKey
    ? uri + (uri.includes('?') ? '&' : '?') + 'cb=' + reloadKey
    : uri;

  // Log tylko przy zmianie finalUri
  if (lastUriLogRef.current !== finalUri) {
    console.log('[GodotView] Using WebView uri=' + finalUri);
    lastUriLogRef.current = finalUri;
  }

  // Auto reload jeśli brak Module i canvas (jednorazowo)
  useEffect(() => {
    if (Platform.OS === 'web') return;
    if (reloadTriedRef.current) return;
    if (canvasDetected || moduleSeen) return;
    const id = setTimeout(() => {
      if (!canvasDetected && !moduleSeen && !reloadTriedRef.current) {
        reloadTriedRef.current = true;
        pushConsole('warn', 'Auto reload with cache-bust (no module & no canvas)');
        console.log('[GodotView] Auto reload (cache-bust)');
        setReloadKey(k => k + 1);
      }
    }, 3200);
    return () => clearTimeout(id);
  }, [canvasDetected, moduleSeen]);

  // Jeśli wykryto krytyczną sytuację (brak wszystkiego) i mamy fallback index.html (tylko HTML) — można go pokazać użytkownikowi dla jasnego komunikatu
  const showInlineFallback =
    effectiveDebug &&
    !canvasDetected &&
    !moduleSeen &&
    !!fallbackIndexHtmlB64 &&
    (indexStatus === 'SKIP(file://)' || indexStatus === 'ERR' || indexStatus === null);

  if (showInlineFallback) {
    const html = atob(fallbackIndexHtmlB64!);
    return (
      <View style={{ flex:1, position:'relative' }}>
        <WebView
          source={{ html: html.replace('</body>',
            '<div style="position:absolute;top:0;left:0;padding:8px;font:12px monospace;color:#fff;background:#900;">' +
            'Diagnostic fallback index.html only – JS/WASM not loaded. Copy web-export folder into native bundle.' +
            '</div></body>') }}
          originWhitelist={['*']}
          style={[{ flex:1 }, style]}
          onLoadEnd={() => {
            if (!loaded) {
              setLoaded(true);
              onReady?.();
            }
          }}
        />
        {Overlay}
      </View>
    );
  }

  return (
    <View style={{ flex: 1, position: 'relative' }}>
      <WebView
        key={reloadKey}                // <--- zapewnia odświeżenie komponentu
        source={{ uri: finalUri }}     // <--- używa finalUri z parametrem cb
        originWhitelist={['*']}
        injectedJavaScriptBeforeContentLoaded={injectedBefore}
        onMessage={onMessage}
        onLoadEnd={() => {
          console.log('[GodotView] onReady (native WebView)');
          setLoaded(true);
          onReady?.();
        }}
        allowFileAccess
        allowingReadAccessToURL="/"
        style={[{ flex: 1 }, style]}
        onError={(e) => {
          const ne = (e as any)?.nativeEvent;
          const m = ne?.description || ne?.message || JSON.stringify(ne);
          pushConsole('error', 'Load error: ' + m);
          console.warn('[GodotView] Failed to load index.html', ne);
        }}
      />
      {Overlay}
    </View>
  );
};

export default GodotView;
