import Foundation

// O antigo `enum TowerKind` (4 torres hardcoded) foi substituído pelo modelo
// data-driven em `TowerCatalog.swift` (21 torres, indexadas por id 0–20). Os
// efeitos-identidade (splash, slow, bounty, burn) agora são campos de `TowerSpec`
// e status de `Status.swift`. Arquivo mantido vazio pra preservar o alvo de build.
