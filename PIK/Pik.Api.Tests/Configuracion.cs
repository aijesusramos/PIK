// Cada FabricaPik pasa su configuración (base temporal, carpeta de fotos, claves) por
// variables de entorno, que son globales del proceso. Si dos clases de prueba corrieran en
// paralelo, una pisaría la configuración de la otra. Por eso corren una tras otra.
[assembly: CollectionBehavior(DisableTestParallelization = true)]
