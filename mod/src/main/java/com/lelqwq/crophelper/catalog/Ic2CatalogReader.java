package com.lelqwq.crophelper.catalog;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import com.lelqwq.crophelper.ApiException;
import com.lelqwq.crophelper.CropHelperMod;

import cpw.mods.fml.common.Loader;
import cpw.mods.fml.common.ModContainer;
import ic2.api.crops.CropCard;
import ic2.api.crops.Crops;

/**
 * 从 IC2 注册表建立目录快照。
 *
 * <p>
 * 注册表通常在启动完成后视为静态。IC2 的同名重注册会用新 CropCard 覆盖旧值且不改变数量，
 * 因此这里按卡对象身份生成签名来检测运行时替换；原地修改 stat/attributes 的卡不受支持。
 * 指纹变化会使 predict 缓存自然失效。
 * </p>
 */
public final class Ic2CatalogReader {

    private static volatile Snapshot cached;

    private Ic2CatalogReader() {}

    public static Catalog get() {
        Crops registry = Crops.instance;
        if (registry == null) {
            throw new ApiException("registry_not_ready", "IC2 crop registry is not initialized");
        }

        Collection<CropCard> cards;
        try {
            cards = registry.getCrops();
        } catch (Throwable t) {
            throw new ApiException("query_failed", "failed to read crop registry: " + describe(t));
        }
        if (cards == null) {
            throw new ApiException("registry_not_ready", "IC2 crop registry returned no collection");
        }

        int size = cards.size();
        if (size == 0) {
            // IC2 启动时会注册基础作物；空目录说明注册尚未完成。
            throw new ApiException("registry_not_ready", "IC2 crop registry is empty");
        }

        long currentSignature = signature(cards, size);
        Snapshot snapshot = cached;
        if (snapshot != null && snapshot.signature == currentSignature) {
            return snapshot.catalog;
        }

        synchronized (Ic2CatalogReader.class) {
            snapshot = cached;
            if (snapshot != null && snapshot.signature == currentSignature) {
                return snapshot.catalog;
            }

            List<Species> species = new ArrayList<Species>(size);
            long builtSignature = size;
            for (CropCard card : cards) {
                builtSignature = builtSignature * 31L + System.identityHashCode(card);
                species.add(toSpecies(card));
            }
            Catalog built = new Catalog(species, modVersions());
            cached = new Snapshot(built, builtSignature);
            return built;
        }
    }

    private static long signature(Collection<CropCard> cards, int size) {
        long signature = size;
        for (CropCard card : cards) {
            signature = signature * 31L + System.identityHashCode(card);
        }
        return signature;
    }

    private static Species toSpecies(CropCard card) {
        if (card == null) {
            throw new ApiException("query_failed", "crop registry contains a null CropCard");
        }

        String owner;
        String name;
        try {
            owner = card.owner();
            name = card.name();
        } catch (Throwable t) {
            throw new ApiException("query_failed", "failed to read crop identity: " + describe(t));
        }
        String label = String.valueOf(owner) + ":" + String.valueOf(name);

        try {
            int tier = card.tier();
            int[] stats = new int[5];
            for (int i = 0; i < 5; i++) {
                stats[i] = card.stat(i);
            }
            String[] attributes = card.attributes();
            int maxSize = card.maxSize();
            String displayName;
            try {
                displayName = card.displayName();
            } catch (Throwable ignored) {
                // 显示名不参与规则，失败时退回原始名。
                displayName = name;
            }
            return new Species(owner, name, displayName, tier, stats, attributes, maxSize);
        } catch (ApiException e) {
            throw e;
        } catch (Throwable t) {
            throw new ApiException("query_failed", "failed to read crop card " + label + ": " + describe(t));
        }
    }

    private static String modVersions() {
        Map<String, ModContainer> mods;
        try {
            mods = Loader.instance()
                .getIndexedModList();
        } catch (Throwable t) {
            return "unknown";
        }
        if (mods == null) {
            return "unknown";
        }

        List<String> ids = new ArrayList<String>(
            Arrays.asList("IC2", "OpenComputers", "cropspp", "Crops++", "gregtech", CropHelperMod.MODID));
        Collections.sort(ids);

        StringBuilder builder = new StringBuilder();
        for (String id : ids) {
            ModContainer container = mods.get(id);
            builder.append(id)
                .append('=')
                .append(container == null ? "absent" : container.getVersion())
                .append(';');
        }
        return builder.toString();
    }

    private static String describe(Throwable t) {
        return t.getClass()
            .getName() + ": "
            + String.valueOf(t.getMessage());
    }

    private static final class Snapshot {

        private final Catalog catalog;
        private final long signature;

        private Snapshot(Catalog catalog, long signature) {
            this.catalog = catalog;
            this.signature = signature;
        }
    }
}
