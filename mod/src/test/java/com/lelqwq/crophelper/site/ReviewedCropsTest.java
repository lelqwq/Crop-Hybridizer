package com.lelqwq.crophelper.site;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class ReviewedCropsTest {

    @Test
    public void collectionRequiresAuditedSeedAndClickMethods() {
        assertTrue(ReviewedCrops.supportsCollection("gregtech.api.util.GTBaseCrop"));
        assertTrue(ReviewedCrops.supportsCollection("ic2.core.crop.CropCoffee"));
        assertTrue(ReviewedCrops.supportsCollection("ic2.core.crop.CropBrownMushroom"));
        assertTrue(ReviewedCrops.supportsCollection("ic2.core.crop.CropWheat"));
        assertFalse(ReviewedCrops.supportsCollection("ic2.core.crop.CropVenomilia"));
        assertFalse(ReviewedCrops.supportsCollection("test.SpecialGTBaseCrop"));
    }

    @Test
    public void acceptsGtReleaseDeclaredByCompanionInTheSameJar() {
        assertTrue(ReviewedCrops.reviewedGtVersion("MC1710", "5.09.51.482", true));
        assertTrue(ReviewedCrops.reviewedGtVersion("5.09.51.482", "absent", false));
        assertFalse(ReviewedCrops.reviewedGtVersion("MC1710", "5.09.51.483", true));
        assertFalse(ReviewedCrops.reviewedGtVersion("MC1710", "absent", true));
        assertFalse(ReviewedCrops.reviewedGtVersion("MC1710", "5.09.51.482", false));
        assertFalse(ReviewedCrops.reviewedGtVersion("other", "5.09.51.482", true));
    }
}
