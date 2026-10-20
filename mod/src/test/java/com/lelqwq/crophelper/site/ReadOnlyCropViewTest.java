package com.lelqwq.crophelper.site;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.fail;

import java.util.HashMap;
import java.util.Map;

import org.junit.Test;

import ic2.api.crops.ICropTile;

public class ReadOnlyCropViewTest {

    @Test
    public void snapshotDoesNotChangeAndDeniesWorldAndMutators() {
        Map<String, Object> values = new HashMap<String, Object>();
        values.put("getSize", (byte) 0);
        values.put("getLightLevel", 9);
        ICropTile view = ReadOnlyCropView.snapshot(values, true);
        values.put("getSize", (byte) 5);
        assertEquals(0, view.getSize());
        assertEquals(9, view.getLightLevel());
        assertFalse(view.isBlockBelow("oreIron"));
        try {
            view.setSize((byte) 5);
            fail("writes must be denied");
        } catch (UnsupportedOperationException expected) {}
        try {
            view.getWorld();
            fail("the real world must not be exposed");
        } catch (UnsupportedOperationException expected) {}
        try {
            view.getNutrients();
            fail("missing environment cache must remain unknown");
        } catch (UnsupportedOperationException expected) {}
    }
}
