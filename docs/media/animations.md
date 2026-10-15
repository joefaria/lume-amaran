# Animações do README

- `temperature.gif`: ciclo de aproximadamente 12 segundos, 15 quadros por segundo. Temperatura entre 2700 e 6500 K, intensidade fixa em 65%, aparência escura.
- `appearance.gif`: ciclo de aproximadamente 5 segundos, 12 quadros por segundo. Alterna entre claro e escuro, mantendo 65% e 4500 K.

São capturas reais da interface nativa SwiftUI, usando o mesmo `Panel` de `Sources/Panel.swift`, com estado ilustrativo em uma janela de demonstração separada. Os materiais e as transições foram capturados pelo compositor do macOS; não foram gerados por IA nem recriados em HTML. Nenhuma luz física foi controlada para produzir as animações, e a demonstração não restaura credenciais do Chaves.

As capturas foram recortadas para os 336 × 396 pixels do painel e codificadas com FFmpeg, paleta de 256 cores e repetição contínua. O README usa `<picture>` com `prefers-reduced-motion: reduce` para apresentar uma captura estática no lugar de cada GIF quando essa preferência está ativa. As capturas estáticas completas também continuam disponíveis na seção expansível.
