package com.megadeep.cubip_rfid

import kotlin.test.Test
import kotlin.test.assertEquals

internal class CubipRfidPluginTest {
    @Test
    fun colombiaCursorsCoverFccChannelsFrom915To928() {
        assertEquals(25, CubipRfidPlugin.COLOMBIA_CURSORS.first())
        assertEquals(49, CubipRfidPlugin.COLOMBIA_CURSORS.last())
        assertEquals(25, CubipRfidPlugin.COLOMBIA_CURSORS.size)
        assertEquals(3, CubipRfidPlugin.FCC_RANGE_INDEX)
    }
}
