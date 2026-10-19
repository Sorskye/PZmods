--Ammo Maker by STIMP_TM

--[[

With the Ammo Maker API, 42.15+ gun mods can assign custom ammo items to Ammo Maker ammo types, and define extra items that will be dropped next to casings when firing specific guns.
Based on the added definitions, Ammo Maker adjusts craft recipes, foraging definitions, item distributions, and other aspects dynamically.

Add `ammomaker_apiTables.lua` to `...\media\lua\shared\` of your 42.15+ gun mod and update `ammoMakerAddAmmoTypesMap0` and `ammoMakerAddDropExtraItemsMap0', according to your requirements.
If Ammo Maker is used in combination with your mod, it will get and add your definitions on start-up.

/!\ Delete or comment out tables that are not in use /!\

If you need to map custom ammo item types or define drop extra items from multiple mods at the same time (e.g. a main mod plus one or more expansion mods), add separate tables to each mod.
Per feature, the API supports up to 10 tables simultaneously and is using the following naming patterns:

    Accepted add ammo types table names:

        ammoMakerAddAmmoTypesMap0 => ammoMakerAddAmmoTypesMap9

    Accepted add drop extra items table names:

        ammoMakerAddDropExtraItemsMap0 => ammoMakerAddDropExtraItemsMap9

If you would like to use the API and your mod was listed as compatible already, please let us know and we will remove the hard coded values for your mod.

    Ammo Maker Ammo Types:

        Modded Types:

            46x30             4.6x30mm - 2001
            545x39            5.45x39mm - 1974
            223Rem            .223 Remington (aka. 5.7x45mm) - 1957
            556x45AP          5.56x45mm NATO armour piercing - 1980
            556x45HP          5.56x45mm NATO hollow point - 1980
            556x45OP          5.56x45mm NATO over pressured - 1980
            556x45SS          5.56x45mm NATO sub sonic - 1980
            57x28             5.7x28mm (aka. FN 5.7x28mm NATO) - 1990
            22LR              .22 long rifle (aka. 5.7x15mmR) - 1887
            58x42             5.8x42mm (aka. DBP87) - 1987
            25ACP             .25 ACP (aka. 6.35x16mmSR or .25 Auto) - 1905
            65x50SRAris       6.5x50mmSR Arisaka (aka. 6.5x51 R) - 1897
            65x52Carc         6.5x52mm Carcano round - 1891
            30Carbine         .30 Carbine (aka. 7.62x33mm) - 1942
            762x38RNag        7.62x38mmR (aka. 7.62mm Nagant) - 1895
            762x51NATO        7.62x51mm NATO (aka. 7.62 NATO) - 1954
            75x54             7.5x54mm (aka. 7.5 French or 7.5 MAS) - 1924
            3006Spring        .30-06 Springfield (aka. 7.62x63mm) - 1906
            762x25Tok         7.62x25mm Tokarev - 1930
            762x39            7.62x39mm (aka. 7.62 Soviet or .30 Russian Short) - 1945
            303British        .303 British (aka. 7.7x56mmR) - 1889
            762x54R           7.62x54mmR - 1891
            32ACP             .32 ACP (aka. 7.65x17mmSR or .32 Auto) - 1899
            792x33Kurz        7.92x33mm Kurz (aka. 7.9mm Kurz or 8x33 Polte) - 1942
            792x57Maus        7.92x57mm Mauser (aka. 8mm Mauser or 8x57mm) - 1905
            8x50RLeb          8x50mmR Lebel (aka. 8mm Lebel) - 1886
            8x27RLeb          8x27mmR Lebel (aka. 8mm French Ordnance) - 1892
            86x43BLK          8.6mm Blackout (aka. 8.6x43mm or 8.6 BLK) - 2022
            338Lapua          .338 Lapua Magnum (aka. 8.6x70mm or 8.58x70mm) - 1989
            380ACP            .380 ACP (aka. 9x17mm or .380 Auto) - 1908
            9x25Maus          9x25mm Mauser (aka. 9mm Mauser Export) - 1904
            9x39              9x39mm round - 1980
            9x18Mak           9x18mm Makarov (aka. 9x18mm PM) - 1946
            410Buck00         .410 bore 00 buckshot - 10.4mm - 1874
            10x25Auto         10mm Auto (aka. 10x25mm) - 1983
            40SW              .40 S&W (aka. 10.2x22mm) - 1990
            4440WCF           .44-40 Winchester (aka. 10.8x33mmR or .44 WCF) - 1873
            45LC              .45 Colt (aka. 11.43x33mmR or .45 Long Colt) - 1872
            4570Gov           .45-70 Government (aka. 11.6x53mmR) - 1872
            50AE              .50 Action Express (aka. 12.7x33mmRB or .50 AE) - 1988
            500SWMag          .500 S&W Magnum (aka. 12.7x41mmSR) - 2003
            50BMG             .50 BMG (aka. 12.7x99mm NATO or .50 Browning) - 1921
            127x55            12.7x55mm (aka. STs-130 or PS-12) - 2002
            20Buck00          20 bore 00 buckshot (aka. 20-gauge) - 15.6mm - 1870
            12Slug            12 bore slug (aka. 12-gauge) - 18.5mm - 1860
            10Buck00          10 bore 00 buckshot (aka. 10-gauge) - 19.7mm - 1830
            4Buck00           4 bore 00 buckshot (aka. 4-gauge) - 26.7mm - 1975
            40mmHE            40mm high explosive grenade - 1961
            40mmINC           40mm incendiary grenade - 1961
            40mmMPB           40mm multi projectile 00 buckshot - 1961

        Base Game Types:

            556x45NATO        5.56x45mm NATO (aka. 5.56 NATO) - 1980
            3030Win           .30-30 Winchester (aka. 7.8x51mmR or .30 WCF) - 1895
            308Win            .308 Winchester (aka. 7.82x51mm) - 1952
            9x19Para          9mm Luger (aka. 9x19mm Parabellum) - 1901
            38SP              .38 Special (aka. 9x29mmR or .38 Spl or .38 Spc) - 1898
            357Mag            .357 Magnum (aka. 9x33mmR) - 1934
            44Mag             .44 Magnum (aka. 10.9x33mmR) - 1950
            45ACP             .45 ACP (aka. 11.43x23mm or .45 Auto) - 1904
            12Buck00          12 bore 00 buckshot (aka. 12-gauge) - 18.5mm - 1860

--]]

--ADD AMMO TYPES

--Map ammo item types for a specific mod.
--Define the ID of your mod and assign the full item type of your ammo items, to Ammo Maker ammo types.
--When mapping ammo item types for multiple mods, use a seperate table with a unique name per mod (...Map0, ...Map1, etc.).
--Do not add base game item types, unless you want to overwrite and re-use them for different calibres than the base game.

ammoMakerAddAmmoTypesMap0 = {
    { modId = "Base", itemType = "Base.762Bullets", ammoType = "762x39" },
};

--ADD DROP EXTRA ITEMS

--Map drop extra items for a specific mod.
--Define the ID of your mod and assign the full item types of your weapon and drop item, to Ammo Maker ammo types.
--When mapping ammo item types for multiple mods, use a seperate table with a unique name per mod (...Map0, ...Map1, etc.).
--Only one drop extra item can be assigned per weapon type

--ammoMakerAddDropExtraItemsMap0 = {
--{ modId = "guns93", weaponType = "Base.M249", itemType = "Base.556BeltLink", ammoType = "556x45NATO" },
--{ modId = "guns93", weaponType = "Base.M60", itemType = "Base.308BeltLink", ammoType = "308Win" },
--};
