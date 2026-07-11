# TODO / Pendientes

Checklist de contenido pendiente o mejoras conocidas en BFA-HavenCore. Formato:
`- [ ] pendiente` / `- [x] hecho`. Agregar items nuevos abajo de la seccion que
corresponda (crear una seccion nueva si no encaja en ninguna). No borrar items
completados, solo tildarlos - sirven de historial de que se reviso.

## Quest 39684 "Beam Me Up" (Glazer / Vault of the Wardens)

- [ ] El stun de Glazer y el kill credit se aplican apenas el jugador
      interactua con el espejo (`go_244449::OnGossipHello`), de forma
      instantanea. En retail el rayo viaja visualmente desde Glazer, rebota
      en el espejo, y recien ahi lo golpea. Falta encadenar la secuencia
      visual antes de aplicar el stun: `go->CastSpell(glazer,
      SPELL_GLAZER_BEAM_VIS_3)` (rayo pasando por el espejo) -> esperar a
      que termine su duracion/viaje -> recien ahi `glazer->AI()->DoAction
      (ACTION_GLAZER_SHIELD_BROKEN)` + `SetControlled(true,
      UNIT_STATE_STUNNED)`. Ver
      `src/server/scripts/BrokenIsles/DemonHunterZones/zone_vault_of_wardens.cpp`
      (`npc_96680` / `go_244449`). Referencia de la secuencia completa con
      lentes intermedios: `src/server/scripts/BrokenIsles/VaultOfTheWardens/boss_glazer.cpp`
      (`npc_glazer_lensAI::SearchBeamTarget`, `SpellHit` case
      `SPELL_BEAM_VIS_4`).
- [ ] Evaluar si vale la pena agregar los orbes de energia "bouncing"
      literales (creature en movimiento) en vez de reusar `SPELL_PULSE_AT`
      cast en el jugador mas cercano - mas fiel a retail pero requiere una
      fila nueva en `creature_template` (ver skill `quest-enemy-behavior`).

## Quest 39685 "Frozen in Time" (Countermeasures / Vault of Ice)

- [ ] Sintoma confirmado: Ash'golm (npc 96681) no hace absolutamente nada
      (mismo caso que Glazer antes del fix - `ScriptName` vacio, `AIName=
      SmartAI` con `smart_scripts` vacia), y las 3 "esferas"/Countermeasures
      (npc 99709/99731/99732, los 3 objetivos de la quest, ver
      `quest_objectives` de 39685) se completan con solo tocarlas: la clase
      `npc_q39685AI::OnSpellClick` (`zone_vault_of_wardens.cpp` linea ~336)
      da `KilledMonsterCredit` instantaneo al hacer spellclick, sin ninguna
      mecanica/animacion intermedia. Falta implementar la mecanica real
      (activar countermeasures contra Ash'golm mientras esta "congelado",
      con su propia animacion, en vez de un click trivial). El TODO del
      propio archivo (lineas 19-38) ya lo describe: "-boss ash'golm script -
      npc 96681 ... he should be 'frozen', and non attackable. -animations
      for countermeasures." Es la siguiente quest en la cadena despues de
      39684 "Beam Me Up".
      Version "hermana" ya scripteada para reusar spell IDs/patrones (mismo
      approach que con Glazer, ver skill `quest-enemy-behavior`): boss real
      de la mazmorra en
      `src/server/scripts/BrokenIsles/VaultOfTheWardens/boss_ashgolm.cpp`
      (`ScriptName=boss_ashgolm`, creature 95886 "Ash'Golm"; el 96681 de la
      quest es una copia sin scriptear para la fase personal/solo, igual que
      pasaba con Glazer 96680 vs 95887).

## Quest 39686 "All The Way Up" (elevador al Hall of Judgment)

- [ ] Reportado: los NPC enemigos a lo largo del elevador no hacen nada, ni
      siquiera al pasar al lado o encima de ellos (sin aggro, sin reaccion).
      Confirmado en DB: la quest en si ya se autocompleta al aceptarla, sin
      requerir subir nada -
      `npc_96675::OnQuestAccept` (`zone_vault_of_wardens.cpp` linea ~404)
      llama `player->KilledMonsterCredit(96814)` (unico objetivo, "Ascend to
      the Hall of Judgment") directo en el accept, no en ningun punto del
      trayecto. Ademas, los NPCs que deberian atacar durante la subida
      (mapa 1468, eje Z ~118 a ~259, spawneados en varias alturas
      consecutivas como si fuera el hueco del elevador) estan todos sin
      scriptear (`ScriptName` vacio, `AIName=SmartAI`, `smart_scripts`
      vacia - 0 filas confirmado para 96645): principalmente **Vault
      Warden** (entry 96645, el mas numeroso, en Z crecientes de ~152 a
      ~259+), tambien **Vault Roach** (101648), **Freed Illidari** (96656),
      **Wrathguard Legate** (97225), **Abyssal Shard** (97228), **Raxx**
      (97330), **Kurloth** (97334), **Altruis the Sufferer** (102391). Falta
      investigar el mecanismo real en retail (subida en plataforma con oleadas
      atacando desde los costados) y luego: (1) hacer que
      `KilledMonsterCredit(96814)` se otorgue al llegar arriba en vez de al
      aceptar la quest, (2) scriptear el aggro/ataque de estos NPCs durante
      el trayecto.

## Quest "Between Us and Freedom" (Bastillax) - duplicada con recompensas distintas

- [x] Reportado: aparecia duplicada en el log, con dos recompensas distintas
      mostradas. Causa confirmada en DB: **habia 4 filas de `quest_template`
      con el mismo `LogTitle`** ("Between Us and Freedom", LogDescription
      "Kill Bastillax and take his power."): IDs **39688, 39694, 40255,
      40256**, todas ofrecidas por el mismo NPC (`creature_queststarter` =
      97644, Kor'vas Bloodthorn) sin ningun filtro que las separe - el
      cliente las listaba las 4 y nada impedia aceptar mas de una. Eran 2
      pares por especializacion, distinguidos solo por
      `RewardDisplaySpell1`: Par A (39688+39694) = 198589 (Havoc), Par B
      (40255+40256) = 185245 (Vengeance) - la "recompensa distinta" que veia
      el usuario.
      **Fix aplicado** (iterado varias veces hasta quedar fiel al original -
      ver `npc_97644` en `zone_vault_of_wardens.cpp` y
      `sql/updates/db_world/2026_07_10_03.sql` a `_05.sql`):
        - `39694`/`40256` (las "sombras") se sacaron de `creature_queststarter`
          por completo y quedan como filas inertes - `npc_96783AI::JustDied`
          (Bastillax) ya usa un OR sobre las 4 quest IDs para el credit/reward,
          asi que alcanza con que una sola este en el quest log/DB.
        - `39688` (Havoc) y `40255` (Vengeance) se dejaron en
          `creature_queststarter`, con un `ExclusiveGroup` negativo
          compartido (-39688) como red de seguridad - hace falta que esten
          registradas para que `Creature::hasQuest()` acepte el click nativo
          de "Aceptar" y para que aparezca el "!" de quest disponible.
        - `npc_97644::OnGossipHello` detecta la especializacion
          (`Player::GetPrimarySpecialization()` vs
          `TALENT_SPEC_DEMON_HUNTER_HAVOC`/`_VENGEANCE`, `Player.h`), corre
          `PrepareGossipMenu` normal (para que se vea el texto de saludo real
          que este NPC ya tenia configurado, `gossip_menu_id` 19012) y
          despues recorta el `QuestMenu` a una sola entrada (la correcta)
          antes de mandarlo - asi se ve el flujo nativo completo: hablar ->
          texto de saludo -> quest listada -> click -> popup de Aceptar con
          la recompensa correcta.
        - De paso goleteando esto se encontro y arreglo un bug de datos
          separado: `AllowableRaces` de las 4 filas tenia un bitmask corrupto
          (incluia Elfo de la Noche pero no Elfo de Sangre, una de las dos
          razas validas de Demon Hunter) - invisible antes porque el
          otorgamiento anterior via `AddQuest()` silencioso se saltaba
          `CanTakeQuest()`; el flujo nativo si lo valida. Corregido a "todas
          las razas" igual que el resto de la cadena (`2026_07_10_05.sql`).
      Confirmado en el juego (personaje Elfo de Sangre): se ve el texto de
      saludo, se puede seleccionar la quest, el popup de aceptar muestra la
      recompensa correcta, y se toma sin error de raza.
      **Gotcha extra encontrado:** el `ExclusiveGroup` de la red de seguridad
      se habia puesto en negativo (`-39688`) copiando una convencion de otros
      forks de TrinityCore, pero en este motor
      `Player::SatisfyQuestExclusiveGroup` (`Player.cpp`) arranca con
      `if (qInfo->GetExclusiveGroup() <= 0) return true;` - los valores no
      positivos son un no-op ahi. Con eso desactivado en silencio, una vez
      aceptada una variante, `OnGossipHello` dejaba de ofrecerla (bien) pero
      el flujo por defecto del motor seguia dejando aceptar la OTRA variante
      en una visita separada - se podia "tomar dos veces", solo que de a una
      por vez en vez de las dos juntas. Arreglado usando un valor **positivo**
      compartido (39688) en `sql/updates/db_world/2026_07_10_06.sql`.
      Confirmado en el juego que ya no se puede tomar mas de una vez.
      Falta confirmar con un personaje Vengeance que recibe la variante 40255
      y no la Havoc.
