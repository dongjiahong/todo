#ifndef NAVIGATOR_CORE_H
#define NAVIGATOR_CORE_H

#include <stddef.h>

typedef void (*nav_event_cb)(const char *event_json);

void NavFreeString(char *p);
char *NavOpen(const char *dataDir);
void NavSetEventCallback(nav_event_cb cb);
char *NavLoadJSON(void);
char *NavSaveTaskJSON(const char *taskJSON);
char *NavCompleteTask(const char *taskID, int done);
char *NavDeleteTask(const char *taskID, int deleted);
char *NavSaveTagJSON(const char *tagJSON);
char *NavDeleteTag(const char *tagID);
char *NavSaveListJSON(const char *listJSON);
char *NavDeleteList(const char *listID);
char *NavClearCompleted(const char *listID);
char *NavSaveAsset(const void *data, int length, const char *ext);
char *NavAssetPath(const char *name);
char *NavStartSync(int serve, int port);
char *NavGeneratePairingCode(void);
char *NavPairWithPeer(const char *ip, int port, const char *code);
char *NavDeletePairedPeer(const char *deviceID);
char *NavSyncWithPeer(const char *deviceID);
void NavSyncNow(void);
char *NavSyncStatusJSON(void);
char *NavExportMarkdown(void);
char *NavImportJSON(const char *raw);

#endif
