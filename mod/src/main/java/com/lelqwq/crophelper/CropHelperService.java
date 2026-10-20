package com.lelqwq.crophelper;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import com.lelqwq.crophelper.catalog.Catalog;
import com.lelqwq.crophelper.catalog.Ic2CatalogReader;
import com.lelqwq.crophelper.catalog.Species;
import com.lelqwq.crophelper.rules.CrossingRules;
import com.lelqwq.crophelper.site.SiteInspector;
import com.lelqwq.crophelper.util.RequestArgs;

import li.cil.oc.api.event.GeolyzerEvent;

/**
 * crop_helper 协议实现。所有操作都是只读查询，不改变世界或作物状态。
 */
public final class CropHelperService {

    public static final int PROTOCOL = 1;

    private static final int DEFAULT_LIMIT = 32;
    private static final int MAX_LIMIT = 64;
    private static final int MAX_CACHE = 64;

    private static final Logger LOG = LogManager.getLogger(CropHelperMod.MODID);

    /**
     * 预测结果按指纹与无序亲本对缓存；容量很小，避免路线搜索重复计算。
     */
    private static final Map<String, Prediction> PREDICTION_CACHE = new LinkedHashMap<String, Prediction>(
        16,
        0.75f,
        true) {

        private static final long serialVersionUID = 1L;

        @Override
        protected boolean removeEldestEntry(Map.Entry<String, Prediction> eldest) {
            return size() > MAX_CACHE;
        }
    };

    private CropHelperService() {}

    public static Map<String, Object> handle(String operation, Map<?, ?> args) {
        return handle(operation, args, null);
    }

    public static Map<String, Object> handle(String operation, Map<?, ?> args, GeolyzerEvent.Analyze event) {
        Map<String, Object> response = new LinkedHashMap<String, Object>();
        response.put("ok", Boolean.TRUE);
        response.put("protocol", PROTOCOL);
        response.put("rules_fingerprint", "");

        try {
            int protocol = RequestArgs.requiredInt(args, "protocol", 0, Integer.MAX_VALUE);
            if (protocol != PROTOCOL) {
                return error(response, "unsupported_protocol", "supported protocol is " + PROTOCOL);
            }

            if (!isSupported(operation)) {
                return error(response, "unsupported_operation", "unknown operation: " + operation);
            }
            if ("info".equals(operation)) {
                return info(response);
            }

            Catalog catalog = Ic2CatalogReader.get();
            response.put("rules_fingerprint", catalog.fingerprint());

            if ("site".equals(operation)) {
                response.put("site", SiteInspector.inspect(event, args, catalog));
                return response;
            }
            if ("catalog".equals(operation)) {
                return catalogPage(response, args, catalog);
            }
            if ("crop".equals(operation)) {
                return crop(response, args, catalog);
            }
            return predict(response, args, catalog);
        } catch (ApiException e) {
            if ("query_failed".equals(e.code())) {
                LOG.warn("crop_helper query failed: " + e.getMessage());
            }
            return error(response, e.code(), e.getMessage());
        } catch (Throwable t) {
            LOG.error("crop_helper request failed (operation=" + operation + ")", t);
            return error(
                response,
                "query_failed",
                t.getClass()
                    .getSimpleName() + ": "
                    + String.valueOf(t.getMessage()));
        }
    }

    private static boolean isSupported(String operation) {
        return "info".equals(operation) || "catalog".equals(operation)
            || "crop".equals(operation)
            || "predict".equals(operation)
            || "site".equals(operation);
    }

    private static Map<String, Object> info(Map<String, Object> response) {
        response.put("mod_version", CropHelperMod.VERSION);
        response.put("operations", Arrays.asList("info", "catalog", "crop", "predict", "site"));
        Catalog catalog = Ic2CatalogReader.get();
        response.put("rules_fingerprint", catalog.fingerprint());
        response.put("catalog_size", catalog.size());
        return response;
    }

    private static Map<String, Object> catalogPage(Map<String, Object> response, Map<?, ?> args, Catalog catalog) {
        int offset = RequestArgs.optionalInt(args, "offset", 0, 0, Integer.MAX_VALUE);
        int limit = RequestArgs.optionalInt(args, "limit", DEFAULT_LIMIT, 1, MAX_LIMIT);
        List<Species> page = catalog.page(offset, limit);

        List<Map<String, Object>> crops = new ArrayList<Map<String, Object>>(page.size());
        for (Species species : page) {
            crops.add(toMap(species));
        }

        response.put("crops", crops);
        response.put("total", catalog.size());
        response.put("offset", offset);
        response.put("limit", limit);
        long next = (long) offset + page.size();
        if (next < catalog.size()) {
            response.put("next_offset", (int) next);
        }
        return response;
    }

    private static Map<String, Object> crop(Map<String, Object> response, Map<?, ?> args, Catalog catalog) {
        String speciesId = RequestArgs.requiredString(args, "species_id");
        Species species = catalog.find(speciesId);
        if (species == null) {
            return error(response, "unknown_crop", "unknown species_id: " + speciesId);
        }
        response.put("crop", toMap(species));
        return response;
    }

    private static Map<String, Object> predict(Map<String, Object> response, Map<?, ?> args, Catalog catalog) {
        String firstId = RequestArgs.requiredString(args, "parent_a");
        String secondId = RequestArgs.requiredString(args, "parent_b");
        Species first = catalog.find(firstId);
        if (first == null) {
            return error(response, "unknown_crop", "unknown parent_a: " + firstId);
        }
        Species second = catalog.find(secondId);
        if (second == null) {
            return error(response, "unknown_crop", "unknown parent_b: " + secondId);
        }

        int offset = RequestArgs.optionalInt(args, "offset", 0, 0, Integer.MAX_VALUE);
        int limit = RequestArgs.optionalInt(args, "limit", DEFAULT_LIMIT, 1, MAX_LIMIT);

        Prediction prediction = prediction(catalog, first, second);
        List<Candidate> all = prediction.candidates;

        int from = Math.min(offset, all.size());
        long end = (long) from + limit;
        int to = end > all.size() ? all.size() : (int) end;

        List<Map<String, Object>> candidates = new ArrayList<Map<String, Object>>(to - from);
        for (int i = from; i < to; i++) {
            Candidate candidate = all.get(i);
            Map<String, Object> entry = new LinkedHashMap<String, Object>();
            entry.put("species_id", candidate.speciesId);
            entry.put("weight", candidate.weight);
            entry.put(
                "probability",
                prediction.totalWeight == 0 ? Double.valueOf(0.0d)
                    : Double.valueOf(candidate.weight / (double) prediction.totalWeight));
            candidates.add(entry);
        }

        response.put("parent_a", first.id);
        response.put("parent_b", second.id);
        response.put("candidates", candidates);
        response.put("total", all.size());
        response.put("total_weight", Long.valueOf(prediction.totalWeight));
        response.put("offset", offset);
        response.put("limit", limit);
        long next = (long) offset + candidates.size();
        if (next < all.size()) {
            response.put("next_offset", (int) next);
        }
        return response;
    }

    private static Prediction prediction(Catalog catalog, Species first, Species second) {
        boolean inOrder = first.id.compareTo(second.id) <= 0;
        String lower = inOrder ? first.id : second.id;
        String upper = inOrder ? second.id : first.id;
        String key = catalog.fingerprint() + "\n" + lower + "\n" + upper;

        synchronized (PREDICTION_CACHE) {
            Prediction cached = PREDICTION_CACHE.get(key);
            if (cached != null) {
                return cached;
            }
        }

        List<Candidate> candidates = new ArrayList<Candidate>();
        long totalWeight = 0;
        for (Species candidate : catalog.species()) {
            int weight = CrossingRules.totalWeight(candidate, first, second);
            if (weight > 0) {
                candidates.add(new Candidate(candidate.id, weight));
                totalWeight += weight;
            }
        }
        Collections.sort(candidates, new Comparator<Candidate>() {

            @Override
            public int compare(Candidate left, Candidate right) {
                if (left.weight != right.weight) {
                    return Integer.compare(right.weight, left.weight);
                }
                return left.speciesId.compareTo(right.speciesId);
            }
        });

        Prediction prediction = new Prediction(candidates, totalWeight);
        synchronized (PREDICTION_CACHE) {
            PREDICTION_CACHE.put(key, prediction);
        }
        return prediction;
    }

    private static Map<String, Object> toMap(Species species) {
        Map<String, Object> entry = new LinkedHashMap<String, Object>();
        entry.put("species_id", species.id);
        entry.put("owner", species.owner);
        entry.put("name", species.name);
        entry.put("display_name", species.displayName);
        entry.put("tier", Integer.valueOf(species.tier));

        List<Integer> stats = new ArrayList<Integer>(5);
        for (int i = 0; i < 5; i++) {
            stats.add(Integer.valueOf(species.stat(i)));
        }
        entry.put("stats", stats);
        entry.put("attributes", new ArrayList<String>(Arrays.asList(species.attributes())));
        entry.put("max_size", Integer.valueOf(species.maxSize));
        return entry;
    }

    private static Map<String, Object> error(Map<String, Object> response, String code, String detail) {
        response.put("ok", Boolean.FALSE);
        response.put("error", code);
        if (detail != null && !detail.isEmpty()) {
            response.put("detail", detail);
        }
        return response;
    }

    private static final class Candidate {

        private final String speciesId;
        private final int weight;

        private Candidate(String speciesId, int weight) {
            this.speciesId = speciesId;
            this.weight = weight;
        }
    }

    private static final class Prediction {

        private final List<Candidate> candidates;
        private final long totalWeight;

        private Prediction(List<Candidate> candidates, long totalWeight) {
            this.candidates = Collections.unmodifiableList(new ArrayList<Candidate>(candidates));
            this.totalWeight = totalWeight;
        }
    }
}
