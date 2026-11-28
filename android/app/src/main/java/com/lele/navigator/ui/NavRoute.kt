package com.lele.navigator.ui

sealed class NavRoute {
    data object Overview : NavRoute()
    data object Today : NavRoute()
    data object Scheduled : NavRoute()
    data object All : NavRoute()
    data object Flagged : NavRoute()
    data object Completed : NavRoute()
    data class CustomList(val listId: String) : NavRoute()
    data object AllTags : NavRoute()
    data class Tag(val tagId: String) : NavRoute()
}
