package com.manus.andre3d.background;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.widget.Toast;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class BackgroundUpdateService extends Service {
    private static final String CHANNEL = "andre3d_updates";
    private static final int NOTIFICATION_ID = 4311;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private volatile boolean running;

    @Override public void onCreate() {
        super.onCreate();
        createChannel();
        startForeground(NOTIFICATION_ID, notification("Atualização em segundo plano", 0, true));
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (running) return START_STICKY;
        String manifestUrl = intent == null ? "" : intent.getStringExtra("manifest_url");
        if (manifestUrl == null || manifestUrl.isEmpty()) {
            stopSelf();
            return START_NOT_STICKY;
        }
        running = true;
        final String url = manifestUrl;
        executor.execute(() -> downloadAll(url));
        return START_STICKY;
    }

    private void downloadAll(String manifestUrl) {
        try {
            byte[] manifestBytes = getBytes(new URL(manifestUrl), 262144);
            JSONObject manifest = new JSONObject(new String(manifestBytes, "UTF-8"));
            JSONArray files = manifest.optJSONArray("files");
            int total = files == null ? 0 : files.length();
            for (int i = 0; i < total; i++) {
                JSONObject entry = files.getJSONObject(i);
                String relative = entry.optString("path", "");
                String url = resolve(manifestUrl, entry.optString("url", ""));
                if (relative.isEmpty() || url.isEmpty()) continue;
                File destination = destinationFor(relative, "pck".equals(entry.optString("kind", "file")));
                if (valid(destination, entry)) {
                    updateProgress(i + 1, total, "Arquivos já atualizados");
                    continue;
                }
                byte[] body = getBytes(new URL(url), 268435456);
                if (!matches(body, entry)) continue;
                writeAtomic(destination, body);
                updateProgress(i + 1, total, "Baixando conteúdo");
            }
            JSONObject client = manifest.optJSONObject("client");
            if (client != null) {
                String apkUrl = resolve(manifestUrl, client.optString("url", ""));
                String version = client.optString("version", "");
                if (!apkUrl.isEmpty() && !version.isEmpty()) {
                    File apk = new File(getFilesDir(), "updates/apk/Andre3D-" + version + ".apk");
                    if (!valid(apk, client)) writeAtomic(apk, getBytes(new URL(apkUrl), 536870912));
                }
            }
            writeAtomic(new File(getFilesDir(), "updates/installed.json"), manifestBytes);
            updateProgress(100, 100, "Atualização concluída; abra o jogo");
        } catch (Exception ignored) {
            updateProgress(0, 0, "Download será retomado quando houver conexão");
        } finally {
            running = false;
            stopForeground(STOP_FOREGROUND_DETACH);
            stopSelf();
        }
    }

    private byte[] getBytes(URL url, int maxBytes) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(30000);
        connection.setReadTimeout(600000);
        connection.setInstanceFollowRedirects(true);
        connection.connect();
        if (connection.getResponseCode() < 200 || connection.getResponseCode() >= 300) throw new Exception("HTTP");
        int expected = connection.getContentLength();
        if (expected > maxBytes) throw new Exception("size");
        InputStream input = new BufferedInputStream(connection.getInputStream());
        ByteArrayOutputStream output = new ByteArrayOutputStream(Math.max(1024, expected));
        byte[] buffer = new byte[65536];
        int read; int total = 0;
        while ((read = input.read(buffer)) >= 0) {
            total += read;
            if (total > maxBytes) throw new Exception("size");
            output.write(buffer, 0, read);
        }
        input.close(); connection.disconnect();
        return output.toByteArray();
    }

    private String resolve(String base, String path) throws Exception {
        return new URL(new URL(base), path).toString();
    }

    private File destinationFor(String relative, boolean pck) {
        File root = new File(getFilesDir(), pck ? "updates/packages" : "updates/files");
        return new File(root, relative);
    }

    private boolean valid(File file, JSONObject entry) throws Exception {
        if (!file.exists() || file.length() != entry.optLong("size", -1)) return false;
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        InputStream in = new BufferedInputStream(new java.io.FileInputStream(file));
        byte[] buffer = new byte[65536]; int read;
        while ((read = in.read(buffer)) >= 0) digest.update(buffer, 0, read);
        in.close();
        return hex(digest.digest()).equalsIgnoreCase(entry.optString("sha256", ""));
    }

    private boolean matches(byte[] data, JSONObject entry) throws Exception {
        if (data.length != entry.optLong("size", -1)) return false;
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        return hex(digest.digest(data)).equalsIgnoreCase(entry.optString("sha256", ""));
    }

    private String hex(byte[] bytes) {
        StringBuilder value = new StringBuilder();
        for (byte b : bytes) value.append(String.format(Locale.US, "%02x", b));
        return value.toString();
    }

    private void writeAtomic(File target, byte[] data) throws Exception {
        File parent = target.getParentFile();
        if (parent != null) parent.mkdirs();
        File temporary = new File(target.getAbsolutePath() + ".tmp");
        FileOutputStream output = new FileOutputStream(temporary);
        output.write(data); output.flush(); output.close();
        if (target.exists()) target.delete();
        if (!temporary.renameTo(target)) throw new Exception("rename");
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(CHANNEL, "Atualizações Andre3D", NotificationManager.IMPORTANCE_LOW);
            getSystemService(NotificationManager.class).createNotificationChannel(channel);
        }
    }

    private Notification notification(String text, int progress, boolean ongoing) {
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, CHANNEL) : new Notification.Builder(this);
        builder.setContentTitle("Andre3D").setContentText(text).setSmallIcon(android.R.drawable.stat_sys_download).setOngoing(ongoing);
        if (progress > 0) builder.setProgress(100, progress, false);
        return builder.build();
    }

    private void updateProgress(int done, int total, String label) {
        int progress = total <= 0 ? 0 : Math.max(0, Math.min(100, done * 100 / total));
        getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, notification(label + " " + progress + "%", progress, true));
    }

    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() { executor.shutdownNow(); super.onDestroy(); }
}
