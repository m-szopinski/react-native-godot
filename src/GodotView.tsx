import React, { useRef, useImperativeHandle } from 'react';
import { requireNativeComponent, UIManager, findNodeHandle, Platform, View, Text } from 'react-native';

// Lazy + fallback (zapobiega Invariant Violation przy braku natywnej integracji)
let NativeGodotView: any;
if (Platform.OS === 'ios' || Platform.OS === 'macos') {
  try {
    NativeGodotView = requireNativeComponent<any>('GodotView');
  } catch (e) {
    console.warn('[react-native-godot] Native component GodotView nie znaleziony. Czy wykonałeś pod install i pełny rebuild? (renderuję placeholder)');
    NativeGodotView = (props: any) => (
      <View style={[{ backgroundColor: '#111', alignItems: 'center', justifyContent: 'center' }, props.style]}>
        <Text style={{ color: '#ccc', fontSize: 12, textAlign: 'center', padding: 8 }}>
          GodotView (native) nie jest zlinkowany.{'\n'}Uruchom: cd ios && pod install, a następnie pełny rebuild.
        </Text>
      </View>
    );
  }
} else {
  // Inne platformy (Android / web) – stub
  NativeGodotView = (props: any) => (
    <View style={[{ backgroundColor: '#220', alignItems: 'center', justifyContent: 'center' }, props.style]}>
      <Text style={{ color: '#ffb347', fontSize: 12, textAlign: 'center', padding: 8 }}>
        GodotView nieobsługiwany na platformie: {Platform.OS}
      </Text>
    </View>
  );
}

export interface GodotViewProps {
    style?: any;
    projectPath?: string;
    mainScene?: string; // jeśli nie podasz: użyta zostanie wbudowana scena demo (res://scenes/TestScene.tscn) z biblioteki lub auto z project.godot jeśli podałeś projectPath
    symbolPrefix?: string;
    symbolPrefixes?: string;
    suppressStubLogs?: boolean;
    autoStart?: boolean;
}

export interface GodotViewRef {
    sendEvent: (event: string) => void;
    ensureEngine: () => void;
    diagnoseStub: () => void;
    setScene: (scene: string) => void;
    forceAttachRenderView: () => void; // NOWE
}

export const GodotView = React.forwardRef<GodotViewRef, GodotViewProps>((props, ref) => {
    const nativeRef = useRef<any>(null);

    function dispatch(commandName: string, fallbackIndex = 0, args: any[] = []) {
        if (!nativeRef.current) return;
        if (Platform.OS !== 'ios' && Platform.OS !== 'macos') return;
        const node = findNodeHandle(nativeRef.current);
        if (!node) return;
        const cfg = UIManager.getViewManagerConfig?.('GodotView');
        if (!cfg) return;
        const commandId =
            cfg.Commands?.[commandName] ??
            (Array.isArray(cfg.Commands) ? cfg.Commands[fallbackIndex] : undefined);
        if (commandId == null) return;
        UIManager.dispatchViewManagerCommand(node, commandId, args);
    }

    useImperativeHandle(ref, () => ({
        sendEvent(event: string) {
            dispatch('sendEventToGodot', 0, [event]);
        },
        ensureEngine() {
            dispatch('ensureEngine', 1, []);
        },
        diagnoseStub() {
            dispatch('diagnoseStub', 2, []);
        },
        setScene(scene: string) {
            dispatch('setScene', 3, [scene]);
        },
        forceAttachRenderView() {
            dispatch('forceAttachRenderView', 4, []);
        }
    }), []);

    return <NativeGodotView
        ref={nativeRef}
        {...props}
        suppressStubLogs={props.suppressStubLogs ?? false}
        autoStart={props.autoStart ?? true}
    />;
});
