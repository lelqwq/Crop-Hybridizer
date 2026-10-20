package com.lelqwq.crophelper;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import com.lelqwq.crophelper.util.OptionMap;

import cpw.mods.fml.common.eventhandler.SubscribeEvent;
import li.cil.oc.api.event.GeolyzerEvent;

/**
 * 只处理带 crop_helper 请求标识的扫描。不取消事件，也不触碰其它字段，
 * 因此普通 geolyzer.analyze 的行为保持不变。
 */
public final class GeolyzerHandler {

    private static final Logger LOG = LogManager.getLogger(CropHelperMod.MODID);

    @SubscribeEvent
    public void onAnalyze(GeolyzerEvent.Analyze event) {
        if (event == null || event.options == null || event.data == null) {
            return;
        }
        Map<String, Object> options;
        try {
            options = OptionMap.normalize(event.options);
        } catch (Throwable t) {
            // 读选项失败时保持普通扫描可用；客户端会按“辅助接口不可用”处理。
            LOG.error("crop_helper failed to read geolyzer options", t);
            return;
        }
        Object rawOperation = options.get("crop_helper");
        String operation;
        if (rawOperation instanceof String) {
            operation = (String) rawOperation;
        } else if (rawOperation instanceof byte[]) {
            operation = new String((byte[]) rawOperation, StandardCharsets.UTF_8);
        } else {
            return;
        }
        if (event.isCanceled()) {
            return;
        }

        Map<String, Object> reply;
        try {
            reply = CropHelperService.handle(operation, options);
        } catch (Throwable t) {
            // 查询接口不允许把服务端线程打崩；最坏情况返回 query_failed。
            LOG.error("crop_helper handler failed for operation " + operation, t);
            reply = new LinkedHashMap<String, Object>();
            reply.put("ok", Boolean.FALSE);
            reply.put("protocol", CropHelperService.PROTOCOL);
            reply.put("rules_fingerprint", "");
            reply.put("error", "query_failed");
            reply.put(
                "detail",
                t.getClass()
                    .getSimpleName() + ": "
                    + String.valueOf(t.getMessage()));
        }
        event.data.put("crop_helper", reply);
    }
}
