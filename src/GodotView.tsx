import { requireNativeComponent, UIManager, findNodeHandle, Platform } from 'react-native';
import React, { useRef } from 'react';

const NativeGodotView = requireNativeComponent('GodotView');

export interface GodotViewProps {
    style?: any;
}

export interface GodotViewRef {
    sendEvent: (event: string) => void;
}

export const GodotView = React.forwardRef<GodotViewRef, GodotViewProps>((props, ref) => {
    const nativeRef = useRef(null);

    React.useImperativeHandle(ref, () => ({
        sendEvent: (event: string) => {
            const node = findNodeHandle(nativeRef.current);
            if (!node) return;

            if (Platform.OS === 'macos' || Platform.OS === 'ios') {
                UIManager.dispatchViewManagerCommand(
                    node,
                    UIManager.getViewManagerConfig('GodotView').Commands.sendEventToGodot,
                    [event]
                );
            } else {
                console.warn('GodotView is only supported on macOS and iOS.');
            }
        }
    }));

    return <NativeGodotView ref={nativeRef} {...props} />;
});
