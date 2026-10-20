package com.lelqwq.crophelper;

import net.minecraftforge.common.MinecraftForge;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import cpw.mods.fml.common.Mod;
import cpw.mods.fml.common.event.FMLInitializationEvent;

/**
 * 服务端辅助模组入口。
 *
 * <p>
 * 刻意只注册 GeolyzerEvent.Analyze 监听器，不新增方块、物品或客户端逻辑。
 * acceptableRemoteVersions = "*" 允许未安装本模组的客户端登录服务器。
 * </p>
 */
@Mod(
    modid = CropHelperMod.MODID,
    name = CropHelperMod.NAME,
    version = CropHelperMod.VERSION,
    acceptedMinecraftVersions = "[1.7.10]",
    acceptableRemoteVersions = "*",
    acceptableSaveVersions = "*",
    dependencies = "required-after:IC2;required-after:OpenComputers")
public final class CropHelperMod {

    public static final String MODID = "crop_helper";
    public static final String NAME = "Crop Helper";
    // 与 gradle.properties 的 RELEASE_VERSION、mcmod.info 的 version 保持一致。
    public static final String VERSION = "0.1.0";

    private static final Logger LOG = LogManager.getLogger(MODID);

    @Mod.EventHandler
    public void init(FMLInitializationEvent event) {
        MinecraftForge.EVENT_BUS.register(new GeolyzerHandler());
        LOG.info("Crop Helper {} loaded; geolyzer bridge registered", VERSION);
    }
}
