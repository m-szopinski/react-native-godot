import React from 'react';
import { Platform } from 'react-native';
import { WebView } from 'react-native-webview';

const INDEX_PATH = 'web-export/index.html';
// NOTE: Native Godot runtime removed – always loading web export.

export interface GodotViewProps {
  style?: any;
  onReady?: () => void;
  source?: any; // legacy no-op
}

export const GodotView: React.FC<GodotViewProps> = ({ style, onReady }) => {
  if (Platform.OS === 'web') {
    return (
      <div style={{ width: '100%', height: '100%', ...(style || {}) }}>
        <iframe
          src={INDEX_PATH}
          title="GodotWeb"
          style={{ border: 'none', width: '100%', height: '100%' }}
          onLoad={onReady}
        />
      </div>
    );
  }

  const uri =
    Platform.OS === 'android'
      ? 'file:///android_asset/web-export/index.html'
      : INDEX_PATH;

  return (
    <WebView
      source={{ uri }}
      originWhitelist={['*']}
      onLoadEnd={onReady}
      allowFileAccess
      allowingReadAccessToURL="/"
      style={style}
      onError={(e) =>
        console.warn('[GodotView] Failed to load index.html', (e as any)?.nativeEvent)
      }
    />
  );
};

export default GodotView;
