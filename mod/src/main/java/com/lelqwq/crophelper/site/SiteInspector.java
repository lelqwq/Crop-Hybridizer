package com.lelqwq.crophelper.site;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import net.minecraft.tileentity.TileEntity;
import net.minecraft.util.MathHelper;
import net.minecraft.world.World;

import com.lelqwq.crophelper.ApiException;
import com.lelqwq.crophelper.catalog.Catalog;
import com.lelqwq.crophelper.catalog.Species;
import com.lelqwq.crophelper.rules.CrossingRules;
import com.lelqwq.crophelper.util.RequestArgs;

import ic2.api.crops.CropCard;
import ic2.api.crops.Crops;
import ic2.api.crops.ICropTile;
import li.cil.oc.api.event.GeolyzerEvent;

/** 原教程工位的现场查询；只接受本次扫描的真实水平相邻位置。 */
public final class SiteInspector {

    private static volatile Thread serverThread;

    private SiteInspector() {}

    public static void onServerTick() {
        serverThread = Thread.currentThread();
    }

    public static Map<String, Object> inspect(GeolyzerEvent.Analyze event, Map<?, ?> args, Catalog catalog) {
        if (event == null || event.host == null) throw new ApiException("site_unavailable", "scan context is required");
        if (Thread.currentThread() != serverThread) {
            throw new ApiException("site_unavailable", "world query requires the server tick thread");
        }
        for (String key : new String[] { "x", "y", "z" }) {
            if (args.containsKey(key))
                throw new ApiException("invalid_argument", "remote coordinates are not accepted");
        }
        String first = optionalId(args, "parent_a", catalog);
        String second = optionalId(args, "parent_b", catalog);
        if ((first == null) != (second == null)) {
            throw new ApiException("invalid_argument", "parent_a and parent_b must be provided together");
        }
        String candidate = optionalId(args, "candidate", catalog);
        World world = event.host.world();
        if (world == null || world.isRemote) throw new ApiException("site_unavailable", "server world is required");
        int[][] positions;
        try {
            positions = SiteChecks.positions(
                MathHelper.floor_double(event.host.xPosition()),
                MathHelper.floor_double(event.host.yPosition()),
                MathHelper.floor_double(event.host.zPosition()),
                event.x,
                event.y,
                event.z);
        } catch (IllegalArgumentException e) {
            throw new ApiException("invalid_argument", e.getMessage());
        }
        for (int[] position : positions) {
            if (!world.blockExists(position[0], position[1], position[2])) {
                throw new ApiException("site_unavailable", "site chunk is not loaded");
            }
        }

        List<Map<String, Object>> checks = new ArrayList<Map<String, Object>>();
        ICropTile center = read(world, positions[0], "center", checks);
        ICropTile left = read(world, positions[1], "left", checks);
        ICropTile right = read(world, positions[2], "right", checks);
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("layout", "tutorial_three_crops");
        result.put("scope", "current_site_only");
        result.put("dimension", world.provider.dimensionId);
        result.put("center", describe(center, positions[0]));
        result.put("left", describe(left, positions[1]));
        result.put("right", describe(right, positions[2]));
        Map<String, Object> collection = ReviewedCrops.collection(center == null ? null : center.getCrop(), center);
        result.put("collection", collection);
        result.put("ready_for_collection", "pass".equals(collection.get("status")));
        result.put("seed_drop_guaranteed", false);
        boolean emptyCenter = center != null && center.getCrop() == null;
        checks.add(
            SiteChecks.check(
                "empty_center",
                center == null ? "unknown" : emptyCenter ? "pass" : "blocked",
                emptyCenter ? "center_has_no_crop" : "empty_center_required"));
        if (center != null) {
            try {
                boolean upgraded = center.getClass()
                    .getField("upgraded")
                    .getBoolean(center);
                checks.add(
                    SiteChecks.check(
                        "cross_sticks",
                        upgraded ? "pass" : "blocked",
                        upgraded ? "double_crop_sticks" : "double_crop_sticks_required"));
            } catch (ReflectiveOperationException e) {
                checks.add(SiteChecks.check("cross_sticks", "unknown", "cross_sticks_flag_unavailable"));
            }
        }
        String actualLeft = id(left);
        String actualRight = id(right);
        if (first == null) {
            first = actualLeft;
            second = actualRight;
        }
        result.put("parent_a", first);
        result.put("parent_b", second);
        if (left == null || right == null) {
            checks.add(SiteChecks.check("parents_match", "unknown", "parent_tile_not_observed"));
        } else if (actualLeft == null || actualRight == null) {
            checks.add(SiteChecks.check("parents_match", "blocked", "two_planted_parents_required"));
        } else {
            boolean match = SiteChecks.parentsMatch(actualLeft, actualRight, first, second);
            checks.add(
                SiteChecks.check(
                    "parents_match",
                    match ? "pass" : "blocked",
                    match ? "planned_pair_matches" : "planned_pair_differs_from_live_parents"));
        }
        for (int i = 3; i < positions.length; i++) {
            int[] p = positions[i];
            TileEntity tile = world.getTileEntity(p[0], p[1], p[2]);
            if (tile instanceof ICropTile && !"ic2.core.crop.TileEntityCrop".equals(
                tile.getClass()
                    .getName())) {
                checks.add(SiteChecks.check("extra_neighbor_" + i, "unknown", "unreviewed_tile_class"));
                continue;
            }
            boolean extra = tile instanceof ICropTile && ((ICropTile) tile).getCrop() != null;
            checks.add(
                SiteChecks.check(
                    "extra_neighbor_" + i,
                    extra ? "blocked" : "pass",
                    extra ? "unplanned_adjacent_crop" : "no_extra_parent"));
        }
        for (int i = 0; i < 2; i++) {
            String name = i == 0 ? "left" : "right";
            ICropTile tile = i == 0 ? left : right;
            CropCard card = tile == null ? null : tile.getCrop();
            checks.add(
                emptyCenter ? ReviewedCrops.test(name + "_can_grow_at_center", card, center, false)
                    : SiteChecks.check(name + "_can_grow_at_center", "unknown", "empty_center_required"));
            checks.add(ReviewedCrops.test(name + "_can_cross", card, tile, true));
        }
        if (candidate != null) {
            Species species = catalog.find(candidate);
            CropCard card = Crops.instance.getCropCard(species.owner, species.name);
            result.put("candidate", candidate);
            Species firstSpecies = catalog.find(actualLeft);
            Species secondSpecies = catalog.find(actualRight);
            if (firstSpecies == null || secondSpecies == null) {
                checks.add(SiteChecks.check("candidate_weight", "unknown", "parent_tile_not_observed"));
            } else {
                int weight = CrossingRules.totalWeight(species, firstSpecies, secondSpecies);
                result.put("candidate_weight", weight);
                checks.add(
                    SiteChecks.check(
                        "candidate_weight",
                        weight > 0 ? "pass" : "blocked",
                        weight > 0 ? "positive_candidate_weight" : "candidate_weight_zero"));
            }
            checks.add(
                emptyCenter ? ReviewedCrops.test("candidate_can_grow_at_center", card, center, false)
                    : SiteChecks.check("candidate_can_grow_at_center", "unknown", "empty_center_required"));
        }
        result.put("checks", checks);
        String status = SiteChecks.status(checks);
        result.put("status", status);
        result.put("ready_for_crossing", "pass".equals(status));
        // canGrow(空中央位) 不代表后续成熟和取种可靠，不能授权自动收获。
        result.put("automation_ready", false);
        result.put("harvest_status", collection.get("status"));
        result.put("distribution_complete", false);
        return result;
    }

    private static String optionalId(Map<?, ?> args, String key, Catalog catalog) {
        if (!args.containsKey(key)) return null;
        String id = RequestArgs.requiredString(args, key);
        if (catalog.find(id) == null) throw new ApiException("unknown_crop", "unknown " + key + ": " + id);
        return id;
    }

    private static ICropTile read(World world, int[] p, String name, List<Map<String, Object>> checks) {
        TileEntity tile = world.getTileEntity(p[0], p[1], p[2]);
        if (!(tile instanceof ICropTile)) {
            checks.add(SiteChecks.check(name + "_crop_sticks", "blocked", "crop_sticks_missing"));
            return null;
        }
        if (!"ic2.core.crop.TileEntityCrop".equals(
            tile.getClass()
                .getName())) {
            checks.add(SiteChecks.check(name + "_crop_sticks", "unknown", "unreviewed_tile_class"));
            return null;
        }
        checks.add(SiteChecks.check(name + "_crop_sticks", "pass", "crop_tile_present"));
        return (ICropTile) tile;
    }

    private static String id(ICropTile tile) {
        CropCard card = tile == null ? null : tile.getCrop();
        return card == null ? null : card.owner() + ":" + card.name();
    }

    private static Map<String, Object> describe(ICropTile tile, int[] position) {
        Map<String, Object> result = new LinkedHashMap<String, Object>();
        result.put("x", position[0]);
        result.put("y", position[1]);
        result.put("z", position[2]);
        if (tile != null) {
            result.put("species_id", id(tile));
            result.put("size", tile.getSize());
            result.put("growth", tile.getGrowth());
            result.put("gain", tile.getGain());
            result.put("resistance", tile.getResistance());
            result.put("light", tile.getLightLevel());
        }
        return result;
    }
}
