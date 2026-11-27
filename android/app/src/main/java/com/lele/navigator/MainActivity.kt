package com.lele.navigator

import android.app.Activity
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.lele.navigator.model.DateUtils
import com.lele.navigator.ui.*
import com.lele.navigator.ui.components.ThingsMagicFab
import com.lele.navigator.ui.theme.NavigatorThingsTheme
import com.lele.navigator.ui.theme.ThingsTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val vm: NavigatorViewModel = viewModel()
            val state by vm.state.collectAsState()
            val systemDark = isSystemInDarkTheme()
            val dark = when (state.appearanceMode) {
                "light" -> false
                "dark" -> true
                else -> systemDark
            }
            val view = LocalView.current
            if (!view.isInEditMode) {
                SideEffect {
                    val window = (view.context as? Activity)?.window ?: return@SideEffect
                    val controller = WindowCompat.getInsetsController(window, view)
                    controller.isAppearanceLightStatusBars = !dark
                    controller.isAppearanceLightNavigationBars = !dark
                }
            }
            NavigatorThingsTheme(darkTheme = dark) {
                NavigatorRoot(vm = vm)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NavigatorRoot(vm: NavigatorViewModel = viewModel()) {
    val c = ThingsTheme.colors
    val context = LocalContext.current
    val state by vm.state.collectAsState()
    var route by remember { mutableStateOf<NavRoute>(NavRoute.Today) }
    var openTaskId by remember { mutableStateOf<String?>(null) }
    var quickQuery by remember { mutableStateOf("") }
    var showCapture by remember { mutableStateOf(false) }
    var showSearch by remember { mutableStateOf(false) }
    var showSyncSheet by remember { mutableStateOf(false) }
    var showSettingsSheet by remember { mutableStateOf(false) }
    var showTagSheet by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    var lastBackPressMs by remember { mutableLongStateOf(0L) }

    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    val detailTask = openTaskId?.let { id -> state.liveTasks.firstOrNull { it.id == id } }
    LaunchedEffect(openTaskId, detailTask) {
        if (openTaskId != null && detailTask == null) {
            openTaskId = null
        }
    }

    LaunchedEffect(state.undoMessage) {
        val msg = state.undoMessage ?: return@LaunchedEffect
        val res = snackbarHostState.showSnackbar(
            message = msg.text,
            actionLabel = if (msg.undo != null) "撤销" else null,
            duration = SnackbarDuration.Short
        )
        if (res == SnackbarResult.ActionPerformed) {
            msg.undo?.invoke()
        }
        vm.clearUndo()
    }

    // Single always-mounted BackHandler so Android 15 Predictive Back never loses registration
    BackHandler(enabled = true) {
        when {
            openTaskId != null -> openTaskId = null
            showSearch -> {
                showSearch = false
                vm.setSearch("")
            }
            route == NavRoute.Overview && quickQuery.isNotEmpty() -> {
                quickQuery = ""
            }
            route != NavRoute.Overview -> {
                showSearch = false
                vm.setSearch("")
                route = NavRoute.Overview
            }
            else -> {
                val now = System.currentTimeMillis()
                if (now - lastBackPressMs < 2000L) {
                    (context as? Activity)?.finish()
                } else {
                    lastBackPressMs = now
                    Toast.makeText(context, "再按一次退出", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    if (detailTask != null) {
        TaskDetailScreen(
            task = detailTask,
            tags = state.liveTags,
            vm = vm,
            onBack = { openTaskId = null }
        )
    } else {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(if (route == NavRoute.Overview) c.hubBackground else c.listBackground)
        ) {
            AnimatedContent(
                targetState = route,
                transitionSpec = {
                    val goingToOverview = targetState == NavRoute.Overview
                    if (goingToOverview) {
                        (slideInHorizontally(tween(220)) { -it / 5 } + fadeIn(tween(220)))
                            .togetherWith(slideOutHorizontally(tween(220)) { it / 4 } + fadeOut(tween(180)))
                    } else {
                        (slideInHorizontally(tween(220)) { it / 4 } + fadeIn(tween(220)))
                            .togetherWith(slideOutHorizontally(tween(220)) { -it / 5 } + fadeOut(tween(180)))
                    }
                },
                label = "routeTransition"
            ) { targetRoute ->
                when (targetRoute) {
                    NavRoute.Overview -> OverviewScreen(
                        state = state,
                        vm = vm,
                        quickQuery = quickQuery,
                        onQuickQueryChange = { quickQuery = it },
                        onNavigate = { next ->
                            showSearch = false
                            vm.setSearch("")
                            route = next
                        },
                        onOpenTask = { openTaskId = it },
                        onOpenSync = { showSyncSheet = true },
                        onOpenSettings = { showSettingsSheet = true },
                        onOpenTagManager = { showTagSheet = true }
                    )

                    else -> {
                        PullToRefreshBox(
                            isRefreshing = refreshing,
                            onRefresh = {
                                refreshing = true
                                vm.syncNow()
                                scope.launch {
                                    delay(600)
                                    refreshing = false
                                }
                            },
                            modifier = Modifier.fillMaxSize()
                        ) {
                            TaskListScreen(
                                route = targetRoute,
                                state = state,
                                vm = vm,
                                showSearch = showSearch,
                                onToggleSearch = {
                                    showSearch = !showSearch
                                    if (!showSearch) vm.setSearch("")
                                },
                                onBackToLists = {
                                    showSearch = false
                                    vm.setSearch("")
                                    route = NavRoute.Overview
                                },
                                onOpenTask = { openTaskId = it },
                                onOpenSync = { showSyncSheet = true }
                            )
                        }
                    }
                }
            }

            if (route != NavRoute.Logbook) {
                ThingsMagicFab(
                    onClick = { showCapture = true },
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .navigationBarsPadding()
                        .padding(end = 22.dp, bottom = if (route == NavRoute.Overview) 68.dp else 22.dp)
                )
            }

            SnackbarHost(
                hostState = snackbarHostState,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .navigationBarsPadding()
                    .padding(
                        start = 16.dp,
                        end = 16.dp,
                        bottom = when {
                            route == NavRoute.Logbook -> 16.dp
                            route == NavRoute.Overview -> 132.dp
                            else -> 88.dp
                        }
                    )
            ) { data ->
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = if (c.isDark) Color(0xFF2D323E) else Color(0xFF1F2430),
                    contentColor = Color.White,
                    shadowElevation = 6.dp
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = data.visuals.message,
                            fontSize = 14.sp,
                            color = Color.White,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        data.visuals.actionLabel?.let { label ->
                            Spacer(Modifier.width(12.dp))
                            Text(
                                text = label,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Color(0xFF66A3FF),
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .clickable { data.performAction() }
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                }
            }
        }
    }

    if (showCapture) {
        val defaultStatus = if (route == NavRoute.Doing) "doing" else "todo"
        val defaultDue = if (route == NavRoute.Today) DateUtils.presetDue(0, 18) else null
        val defaultTags = if (route is NavRoute.Tag) listOf((route as NavRoute.Tag).tagId) else emptyList()
        QuickCaptureSheet(
            tags = state.liveTags,
            defaultStatus = defaultStatus,
            defaultDue = defaultDue,
            defaultTagIds = defaultTags,
            onDismiss = { showCapture = false },
            onSave = { title, status, tagIds, dueAt ->
                vm.createTask(title, status, tagIds, dueAt)
            }
        )
    }

    if (showSyncSheet) {
        SyncPairingSheet(
            state = state,
            onDismiss = { showSyncSheet = false },
            onPair = { code, addr -> vm.pairWithMac(code, addr) },
            onSyncNow = { vm.syncNow() }
        )
    }

    if (showSettingsSheet) {
        SettingsSheet(
            state = state,
            vm = vm,
            onDismiss = { showSettingsSheet = false },
            onOpenSync = {
                showSettingsSheet = false
                showSyncSheet = true
            }
        )
    }

    if (showTagSheet) {
        TagManagerSheet(
            tags = state.liveTags,
            onCreateTag = { label, hue -> vm.createTag(label, hue) },
            onDeleteTag = { id -> vm.deleteTag(id) },
            onDismiss = { showTagSheet = false }
        )
    }
}
