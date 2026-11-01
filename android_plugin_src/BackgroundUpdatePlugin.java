package com.manus.andre3d.background;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import java.util.Arrays;
import java.util.List;

public final class BackgroundUpdatePlugin extends GodotPlugin {
    private String manifestUrl = "";

    public BackgroundUpdatePlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "BackgroundUpdate";
    }

    @Override
    public List<String> getPluginMethods() {
        return Arrays.asList("configure_background_update", "start_background_update", "stop_background_update");
    }

    @UsedByGodot
    public void configure_background_update(String url) {
        manifestUrl = url == null ? "" : url;
        getContext().getSharedPreferences("andre3d_background_update", Context.MODE_PRIVATE)
                .edit().putString("manifest_url", manifestUrl).apply();
    }

    @UsedByGodot
    public void start_background_update(String url) {
        configure_background_update(url);
        startService();
    }

    @UsedByGodot
    public void stop_background_update() {
        getContext().stopService(new Intent(getContext(), BackgroundUpdateService.class));
    }

    @Override
    public void onMainPause() {
        super.onMainPause();
        startService();
    }

    private void startService() {
        String url = manifestUrl;
        if (url == null || url.isEmpty()) {
            url = getContext().getSharedPreferences("andre3d_background_update", Context.MODE_PRIVATE)
                    .getString("manifest_url", "");
        }
        if (url == null || url.isEmpty()) return;
        Intent intent = new Intent(getContext(), BackgroundUpdateService.class);
        intent.putExtra("manifest_url", url);
        if (Build.VERSION.SDK_INT >= 26) getContext().startForegroundService(intent);
        else getContext().startService(intent);
    }
}
