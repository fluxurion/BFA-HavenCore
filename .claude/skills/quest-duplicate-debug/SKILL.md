---
name: quest-duplicate-debug
description: Use when a quest appears duplicated in the player's quest log in this TrinityCore-based core (BFA-HavenCore) — same title/objective text shown twice (e.g. as entries "1" and "2") right after accepting it, a quest gets "taken twice" (even one-at-a-time across separate visits), or shows two different rewards. Covers how to find the second (or third/fourth) quest_template row causing it, why QUEST_FLAGS_TRACKING does NOT hide a quest from the client log in this codebase, how to safely remove a redundant AddQuest call, and — for NPCs that offer several near-identical variants directly via creature_queststarter (e.g. per-spec quest pairs) — how to build a spec-aware native quest-offer popup and the two easy-to-miss DB gotchas that silently defeat it: ExclusiveGroup only works with positive values in this engine, and Player::AddQuest() bypasses CanTakeQuest() eligibility checks (race/class/etc.) that the native accept flow enforces for real. Based on fixing "Forged in Fire" (39683/40254) and "Between Us and Freedom" (39688/39694/40255/40256) in zone_vault_of_wardens.cpp.
---

# Diagnosticar quests duplicadas en el log (TrinityCore / BFA-HavenCore)

Síntoma: al aceptar una quest, aparece dos veces en el log del cliente con el
mismo título y el mismo texto de objetivo (ej. "0/1 Immolanth slain & power
taken" como entradas 1 y 2). Esto pasó con la quest "Forged in Fire"
(`quest 39683` / `quest 40254` en
`src/server/scripts/BrokenIsles/DemonHunterZones/zone_vault_of_wardens.cpp`).

## 1. Confirmar que son dos filas distintas en `quest_template`

Buscá por el título exacto (¡el duplicado casi siempre es un segundo `ID` con
el mismo `LogTitle`/`LogDescription`!):

```sql
SELECT ID, LogTitle FROM quest_template WHERE LogTitle LIKE '%<texto de la quest>%';
```

Si aparecen dos (o más) IDs con el mismo `LogTitle`, comparalos:

```sql
SELECT ID, QuestID, Type, `Order`, ObjectID, Amount, Description
FROM quest_objectives WHERE QuestID IN (<id1>,<id2>) ORDER BY QuestID, `Order`;

SELECT ID, LogTitle, LogDescription, Flags, FlagsEx FROM quest_template WHERE ID IN (<id1>,<id2>);
```

Normalmente uno de los dos es la quest "real" (tiene cadena:
`quest_template_addon.PrevQuestID`/`NextQuestID` distintos de 0, y aparece en
`creature_queststarter`) y el otro es una copia "fantasma" sin cadena propia
(`PrevQuestID=0`, `NextQuestID=0`) que **no** tiene su propio `creature_queststarter`
— solo aparece en `creature_questender` junto con la real.

## 2. Encontrar quién agrega la copia fantasma

El patrón de este fork es un `OnQuestAccept` que agrega la segunda quest a
mano apenas el jugador acepta la primera:

```cpp
bool OnQuestAccept(Player* player, Creature* creature, Quest const* quest) override
{
    if (quest->GetQuestId() == <id1>)
        if (const Quest* quest = sObjectMgr->GetQuestTemplate(<id2>))
            player->AddQuest(quest, nullptr); // <- esto duplica el log
    ...
}
```

Buscalo con:

```bash
grep -rn "<id1>\|<id2>" src/server/scripts/
```

Normalmente el motivo de agregar la segunda quest es otorgar una recompensa
"de la otra especialización" (spell de desbloqueo de artefacto, etc.) — mirá
el script del NPC/boss cuya muerte da el kill credit (`JustDied`) para
confirmar el propósito real:

```cpp
// dos "quest ids" y dos "reward spells" en paralelo
QUEST1 = <id1>, QUEST2 = <id2>,
CREDIT1 = ..., CREDIT2 = ...,
REWARD_SPELL1 = ..., REWARD_SPELL2 = ...,

void JustDied(Unit* killer) override
{
    ...
    if (plr->GetQuestStatus(QUEST1) == QUEST_STATUS_INCOMPLETE ||
        plr->GetQuestStatus(QUEST2) == QUEST_STATUS_INCOMPLETE)
    {
        plr->KilledMonsterCredit(CREDIT1);
        plr->KilledMonsterCredit(CREDIT2);
        plr->CastSpell(plr, REWARD_SPELL1, true);
        plr->CastSpell(plr, REWARD_SPELL2, true);
    }
}
```

**Dato clave: el `||` significa que alcanza con que el jugador tenga SOLO la
quest real (`QUEST1`) incompleta para que se otorguen AMBAS recompensas.**
La quest fantasma (`QUEST2`) casi nunca es necesaria para que la lógica de
recompensa funcione — solo existía para que, en teoría, quedara "trackeada"
en el log también. Confirmalo grepeando el ID de la quest fantasma en TODO
`src/server/` — si no aparece en ningún otro lado más que en el
`AddQuest`/enum de arriba, no tiene ninguna otra dependencia.

## 3. Gotcha — `QUEST_FLAGS_TRACKING` NO oculta la quest del log en este codebase

Es tentador pensar que la solución es ponerle el flag `QUEST_FLAGS_TRACKING`
(`0x400`) a la quest fantasma, porque el comentario en
`src/server/game/Quests/QuestDef.h` dice literalmente *"these quests ... will
never appear in quest log client side"*. **Esto es engañoso en este fork: no
hay ningún código que filtre el log enviado al cliente según ese flag.**

Confirmalo con:

```bash
grep -rn "QUEST_FLAGS_TRACKING" src/server/game/
```

Vas a encontrar que el único uso real está en
`Player::CompleteQuest` (`Player.cpp`, ~línea 16388): cuando la quest se
completa, si tiene el flag, se llama a `RewardQuest(...)` automáticamente sin
pasar por un NPC de entrega. **Eso es todo lo que hace.** No existe lógica
que oculte el slot de quest log del jugador ni el paquete que arma el
cliente — los slots de quest log viajan como campos de actualización del
objeto jugador sin filtrar por flags. Poner el flag no arregla el duplicado
visual (ya se probó: se aplicó el flag vía SQL, se reinició el worldserver, y
la quest seguía duplicándose).

## 4. Fix correcto: no agregar la quest fantasma en absoluto

Si el paso 2 confirmó que la quest fantasma no tiene otras dependencias, la
solución simple es borrar el `player->AddQuest(quest, nullptr)` (dejar un
comentario bilingüe explicando por qué, para que no lo vuelvan a agregar
"para trackearla mejor"). La lógica de `JustDied` con el `||` ya cubre el
otorgamiento de ambas recompensas usando solo el estado de la quest real.

```cpp
// EN: Quest <id2> is a hidden duplicate of <id1> used only to grant the
// off-spec reward spell (see <NPC>::JustDied). Silently adding it to the
// player's quest log made the quest appear twice in the client UI. Not
// needed: JustDied already grants both rewards based on <id1>'s status
// alone (QUEST1||QUEST2 check), so nothing is lost by removing this.
// ES: La quest <id2> es una copia oculta de <id1> que solo servía para
// otorgar el hechizo de recompensa de la otra especialización (ver
// <NPC>::JustDied). Agregarla en silencio duplicaba la quest en el
// cliente. No hace falta: JustDied ya otorga ambas recompensas usando
// solo el estado de <id1>, asi que no se pierde nada al quitarla.
```

Recompilá con el loop rápido (`docker compose run --rm dev-builder`),
reiniciá `worldserver` (`docker restart bfacore-worldserver`, tarda
~1.5 min en recargar mapas/quests antes de aceptar conexiones), y probá
aceptar la quest de nuevo en el juego.

## 5. Si la quest fantasma SÍ tiene otras dependencias

Si el grep del paso 2 muestra que el ID de la quest fantasma se usa en otro
lado (otro script chequea `GetQuestStatus(<id2>)`, o hay una cadena
`PrevQuestID`/`NextQuestID` real), no la borres — en ese caso evaluá:

- Si de verdad necesita ocupar un slot de quest log visible distinto (dos
  quests con objetivos distintos, no un duplicado de texto), el "bug" no es
  tal: cada una debería tener su propio `LogTitle` claro, no copiar el de la
  otra.
- Si sí es una quest puramente interna que otro script necesita como
  "bandera" de estado, considerá reemplazarla por una condición sin quest
  (aura temporal, flag de personaje, o directamente el chequeo de estado de
  la quest real) en vez de un segundo quest log real.

## 6. Variante distinta: el NPC ofrece varias filas directamente (sin hack de `OnQuestAccept`)

No todos los duplicados son un `AddQuest` escondido. Caso real: "Between Us
and Freedom" (Bastillax) tenía **4 filas** de `quest_template` con el mismo
`LogTitle`/`LogDescription` (39688, 39694, 40255, 40256), las 4 en
`creature_queststarter` del **mismo NPC**, sin ningún `OnQuestAccept` que
agregara nada — el cliente simplemente listaba las 4 en el gossip y nada
impedía aceptar más de una. Eran en realidad 2 pares por especialización
(Havoc/Vengeance), distinguibles solo por `RewardDisplaySpell1` (el "recompensa
distinta" que se veía).

```sql
SELECT ID, RewardDisplaySpell1, RewardDisplaySpell2 FROM quest_template WHERE ID IN (<id1>,<id2>,<id3>,<id4>);
SELECT * FROM creature_queststarter WHERE quest IN (<id1>,<id2>,<id3>,<id4>);
```

Si el script del boss/NPC que otorga el credit (`JustDied` u otro) ya hace un
`||` sobre las 4 quest IDs igual que en el patrón de la sección 2, alcanza con
que **una sola** esté realmente disponible. Este motor **no tiene ningún
`CONDITION_*` para especialización de talentos** (grep `enum ConditionTypes`
en `ConditionMgr.h` para confirmarlo en tu versión), así que la DB sola no
puede filtrar por spec — hace falta un poco de C++.

**Fix que quedó fiel al original** (mostrando el popup nativo de "Aceptar
Quest" con texto de saludo, en vez de un `AddQuest()` silencioso al abrir el
gossip):

1. Sacar de `creature_queststarter` la(s) copia(s) "sombra" que nunca hacen
   falta (en este caso 39694/40256), dejando solo una fila real por variante
   (39688, 40255).
2. Ponerles un `ExclusiveGroup` **compartido** a las variantes que sí quedan
   en `creature_queststarter`, como red de seguridad para el flujo por
   defecto del motor.
3. En `CreatureScript::OnGossipHello` del NPC: si el jugador es elegible,
   `PrepareGossipMenu(creature, gossipMenuId, true)` (corre el flujo normal,
   con el texto de saludo real si el NPC tiene uno vía `gossip_menu_id`),
   después `PlayerTalkClass->GetQuestMenu().ClearMenu()` +
   `AddMenuItem(questIdSegunSpec, 2)` (icono 2 = disponible para aceptar) para
   dejar solo la variante correcta, y `SendPreparedGossip(creature)`.
   `Player::GetPrimarySpecialization()` vs `TALENT_SPEC_DEMON_HUNTER_HAVOC`/
   `_VENGEANCE` (u otro `TALENT_SPEC_*` de `Player.h`) para decidir cuál.

```cpp
bool OnGossipHello(Player* player, Creature* creature) override
{
    if (<elegible: ninguna de las 2 variantes activa ni ya recompensada>)
    {
        uint32 questId = player->GetPrimarySpecialization() == TALENT_SPEC_DEMON_HUNTER_VENGEANCE
            ? QUEST_VENGEANCE : QUEST_HAVOC;

        player->PrepareGossipMenu(creature, creature->GetCreatureTemplate()->GossipMenuId, true);
        player->PlayerTalkClass->GetQuestMenu().ClearMenu();
        player->PlayerTalkClass->GetQuestMenu().AddMenuItem(questId, 2);
        player->SendPreparedGossip(creature);
        return true;
    }
    return false; // deja correr el flujo por defecto (ej. ya la tiene activa/completa)
}
```

### Gotcha A — `ExclusiveGroup` NEGATIVO no hace nada en este motor

Es tentador copiar la convención de "usar un valor negativo compartido" que
se ve en otros forks de TrinityCore. **En este motor no funciona**:
`Player::SatisfyQuestExclusiveGroup` (`Player.cpp`) arranca con

```cpp
if (qInfo->GetExclusiveGroup() <= 0)
    return true; // sin restriccion - no-op
```

Si ponés `ExclusiveGroup = -39688`, la mutua exclusión queda **desactivada en
silencio**: tu `OnGossipHello` va a dejar de ofrecer la variante ya tomada
(porque tenés tu propio chequeo de elegibilidad), pero en cuanto ese chequeo
falle y el flujo caiga al gossip por defecto del motor, `PrepareQuestMenu`
va a seguir listando y dejando aceptar la OTRA variante sin ningún freno —
síntoma: "se puede tomar dos veces, pero de a una, en visitas separadas" (no
las dos juntas como el bug original, pero sigue siendo un duplicado). Usá
siempre un valor **positivo** compartido (ej. la quest ID más baja del grupo).
Verificá el signo correcto en tu propia versión del engine antes de asumir la
convención de otro fork.

### Gotcha B — `Player::AddQuest()` silencioso se salta `CanTakeQuest()` (raza, clase, nivel...)

Si el "fix rápido" para evitar el duplicado fue otorgar la quest con
`player->AddQuest(quest, creature)` directo (como en la sección 4), estás
evitando TODA la validación normal (`CanTakeQuest`: raza, clase, nivel,
reputación, etc.) — así que datos corruptos en el `quest_template` (ej. un
`AllowableRaces` con el bitmask mal armado, faltando una raza válida) quedan
invisibles y la quest "funciona" igual. **En cuanto pasás al flujo nativo de
aceptar** (`HandleQuestgiverAcceptQuestOpcode` → `CanTakeQuest(quest, true)`,
disparado por el popup real de "Aceptar"), esa validación se aplica de
verdad y puede rechazar la quest con mensajes como *"That quest is not
available to your race"* aunque el jugador debería poder tomarla. No es un
bug nuevo que introdujiste vos — es un bug de datos preexistente que estaba
escondido por el `AddQuest()` silencioso. Chequealo con:

```sql
SELECT ID, AllowableRaces FROM quest_template WHERE ID IN (<id1>,<id2>);
-- bit de una raza especifica (ej. Blood Elf = raza 10 = bit 9):
SELECT ID, AllowableRaces & (1<<9) AS blood_elf_bit FROM quest_template WHERE ID IN (<id1>,<id2>);
```

Si el bitmask no es el sentinel de "todas las razas" (`18446744073709551615`)
y no coincide con lo que usan las quests hermanas de la misma cadena,
probablemente esté corrupto — copiá el valor de una quest hermana correcta
de la misma cadena en vez de intentar reconstruir el bitmask a mano.

## Checklist rápido

1. `SELECT ... WHERE LogTitle LIKE '%...%'` — ¿hay dos (o más) `ID` con el
   mismo título/descripción?
2. Comparar `quest_objectives`, `quest_template_addon` (Prev/NextQuestID) y
   `creature_queststarter` de todas — ¿es un `OnQuestAccept` agregando una
   fantasma (sección 2), o el NPC ofrece varias filas directamente sin ningún
   hack (sección 6)?
3. `grep -rn "<id1>\|<id2>\|..." src/server/scripts/` — encontrar el script
   que agrega/otorga cada una, y el que las usa para recompensas (`JustDied`
   u otro, buscando el patrón `||` sobre todas las quest IDs).
4. Si es el patrón de `OnQuestAccept`: `grep -rn "<id_fantasma>" src/server/`
   completo — si no aparece en ningún otro lado, es seguro borrar el
   `AddQuest`.
5. Si es el patrón de variantes por NPC (sección 6): decidí si hace falta el
   popup nativo (`PrepareGossipMenu`+`QuestMenu` filtrado) o alcanza con un
   `AddQuest()` simple — pero si usás `AddQuest()`, revisá `AllowableRaces`/
   `AllowableClasses`/nivel de las variantes ANTES de dar el fix por
   terminado (Gotcha B), porque esos bugs quedan invisibles hasta que alguien
   pase por el flujo nativo.
6. Si usás `ExclusiveGroup` como red de seguridad, verificá el signo correcto
   en `Player::SatisfyQuestExclusiveGroup` de tu propia versión del engine
   antes de asumir que un valor negativo compartido alcanza (Gotcha A).
7. **No confiar en `QUEST_FLAGS_TRACKING` para ocultar del log en este
   codebase** — verificalo vos mismo con grep antes de asumir que el flag
   hace algo del lado del cliente.
8. Recompilar, reiniciar `worldserver`, confirmar en el juego que la quest
   aparece una sola vez (¡en visitas separadas también!) y que las
   recompensas se siguen otorgando igual.
