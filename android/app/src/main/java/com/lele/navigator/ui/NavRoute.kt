package com.lele.navigator.ui

sealed class NavRoute {
    data object Overview : NavRoute()
    data object Today : NavRoute()
    data object Doing : NavRoute()
    data object Todo : NavRoute()
    data object Upcoming : NavRoute()
    data class Tag(val tagId: String) : NavRoute()
    data object Logbook : NavRoute()
}
