-- Configuracion del sistema de almacenamiento.
-- Usa el comando `peripherals` dentro del programa para ver los nombres reales
-- que le dio la red de modems cableados a cada cofre.
return {
  -- Cofre donde tiras los items para que se guarden solos.
  input = "minecraft:chest_0",

  -- Cofre donde aparecen los items que pedis con `get`.
  output = "minecraft:chest_1",

  -- Inventarios de la red que NO forman parte del almacenamiento.
  ignore = {},

  -- Cada cuantos segundos se revisa el cofre de entrada.
  autoStoreInterval = 3,
}
