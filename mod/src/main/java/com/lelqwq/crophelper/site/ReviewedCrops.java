package com.lelqwq.crophelper.site;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import cpw.mods.fml.common.Loader;
import cpw.mods.fml.common.ModContainer;
import ic2.api.crops.CropCard;
import ic2.api.crops.ICropTile;

/**
 * 根据本地实装字节码审核的精确类与版本。拒绝未审核子类，并配合只读 ICropTile
 * 避免向作物卡暴露真实世界、TileEntity 以及任何修改接口。
 */
final class ReviewedCrops {

    private static final Set<String> IC2_CLASSES = new HashSet<String>(
        Arrays.asList(
            "CropAurelia",
            "CropBrownMushroom",
            "CropCarrots",
            "CropCocoa",
            "CropCoffee",
            "CropColorFlower",
            "CropCyprium",
            "CropEating",
            "CropFerru",
            "CropHops",
            "CropMelon",
            "CropNetherWart",
            "CropPlumbiscus",
            "CropPotato",
            "CropPumpkin",
            "CropRedMushroom",
            "CropRedWheat",
            "CropReed",
            "CropShining",
            "CropStagnium",
            "CropStickreed",
            "CropTerraWart",
            "CropVenomilia",
            "CropWeed",
            "CropWheat"));

    private ReviewedCrops() {}

    static Map<String, Object> test(String name, CropCard card, ICropTile tile, boolean cross) {
        if (card == null || tile == null) return SiteChecks.check(name, "unknown", "crop_or_tile_missing");
        String issue = reviewIssue(card);
        if (issue != null) return SiteChecks.check(name, "unknown", issue);
        try {
            ICropTile view = ReadOnlyCropView.of(tile);
            boolean result = cross ? card.canCross(view) : card.canGrow(view);
            return SiteChecks.check(name, result ? "pass" : "blocked", result ? "predicate_true" : "predicate_false");
        } catch (Throwable t) {
            return SiteChecks.check(
                name,
                "unknown",
                t.getClass()
                    .getSimpleName() + ": "
                    + t.getMessage());
        }
    }

    static Map<String, Object> collection(CropCard card, ICropTile tile) {
        String name = "seed_collection";
        if (card == null || tile == null) return SiteChecks.check(name, "blocked", "no_center_crop");
        String issue = reviewIssue(card);
        if (issue != null) return SiteChecks.check(name, "unknown", issue);
        String className = card.getClass()
            .getName();
        if (!supportsCollection(className))
            return SiteChecks.check(name, "unknown", "unreviewed_seed_collection: " + className);
        try {
            ICropTile view = ReadOnlyCropView.of(tile);
            if (!card.canBeHarvested(view)) return SiteChecks.check(name, "blocked", "not_harvestable_yet");
            if ("ic2.core.crop.CropWheat".equals(className) && view.getGrowth() <= 1
                && view.getGain() <= 1
                && view.getResistance() <= 1) {
                return SiteChecks.check(name, "blocked", "vanilla_wheat_seeds_only");
            }
            return SiteChecks.check(name, "pass", "reviewed_pick_with_random_seed_drops");
        } catch (Throwable t) {
            return SiteChecks.check(
                name,
                "unknown",
                t.getClass()
                    .getSimpleName() + ": "
                    + t.getMessage());
        }
    }

    static boolean supportsCollection(String className) {
        // 仅审核这些类的 leftclick/getSeeds/canBeHarvested；不调用掉落函数试算。
        return "gregtech.api.util.GTBaseCrop".equals(className) || "ic2.core.crop.CropCoffee".equals(className)
            || "ic2.core.crop.CropBrownMushroom".equals(className)
            || "ic2.core.crop.CropWheat".equals(className);
    }

    private static String reviewIssue(CropCard card) {
        String className = card.getClass()
            .getName();
        Map<String, ModContainer> mods = Loader.instance()
            .getIndexedModList();
        boolean ic2Class = className.startsWith("ic2.core.crop.")
            && IC2_CLASSES.contains(className.substring("ic2.core.crop.".length()));
        boolean gtClass = "gregtech.api.util.GTBaseCrop".equals(className);
        if (!ic2Class && !gtClass) return "unreviewed_crop_class: " + className;
        ModContainer gt = mods.get("gregtech");
        ModContainer nh = mods.get("gregtech_nh");
        boolean sameSource = gt != null && nh != null
            && gt.getSource() != null
            && gt.getSource()
                .equals(nh.getSource());
        if (!"2.2.828-experimental".equals(version(mods, "IC2"))
            || (gtClass && !reviewedGtVersion(version(mods, "gregtech"), version(mods, "gregtech_nh"), sameSource))) {
            return "unreviewed_crop_version: IC2=" + version(mods, "IC2")
                + "; gregtech="
                + version(mods, "gregtech")
                + "; gregtech_nh="
                + version(mods, "gregtech_nh");
        }
        return null;
    }

    static boolean reviewedGtVersion(String primary, String companion, boolean sameSource) {
        // GT 主模组声明 MC1710；同一 JAR 的 gregtech_nh 才声明发行版本。
        return "5.09.51.482".equals(primary)
            || ("MC1710".equals(primary) && "5.09.51.482".equals(companion) && sameSource);
    }

    private static String version(Map<String, ModContainer> mods, String id) {
        ModContainer mod = mods.get(id);
        return mod == null ? "absent" : mod.getVersion();
    }
}
