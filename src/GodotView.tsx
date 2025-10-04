import React, { useMemo } from 'react';
import { Platform, View } from 'react-native';
import { WebView } from 'react-native-webview';

const INDEX_PATH = 'web-export/index.html';

export interface GodotViewProps {
  style?: any;
  onReady?: () => void;
}

export const GodotView: React.FC<GodotViewProps> = ({ style, onReady }) => {
  const platform = Platform.OS;

  // iOS: spróbuj wyliczyć absolutną ścieżkę (gdy bundlowane jako zasoby)
  const iosFileUri = useMemo(() => {
    if (platform !== 'ios') return null;
    try {
      // @ts-ignore SourceCode może nie być typowany
      const scriptURL: string | undefined = require('react-native').NativeModules?.SourceCode?.scriptURL;
      if (!scriptURL) return null;
      const base = scriptURL.substring(0, scriptURL.lastIndexOf('/'));
      const candidate = base + '/' + INDEX_PATH;
      return candidate.startsWith('file://') ? candidate : 'file://' + candidate;
    } catch {
      return null;
    }
  }, [platform]);

  if (platform === 'web') {
    return (
      <div style={{ width: '100%', height: '100%', ...(style || {}) }}>
        <iframe
          src={INDEX_PATH}
          title="GodotWeb"
          style={{ border: 'none', width: '100%', height: '100%' }}
          onLoad={() => onReady?.()}
        />
      </div>
    );
  }

  const uri =
    platform === 'android'
      ? 'file:///android_asset/web-export/index.html'
      : (iosFileUri || INDEX_PATH);

  return (
    <View style={[{ flex: 1 }, style]}>
      <WebView
        source={{ uri }}
        onLoadEnd={() => onReady?.()}
        originWhitelist={['*']}
        allowFileAccess
        allowingReadAccessToURL="/"
        style={{ flex: 1 }}
      />
    </View>
  );
};

export default GodotView;
