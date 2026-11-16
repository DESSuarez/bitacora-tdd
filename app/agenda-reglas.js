// Reglas de la agenda de producción de Música. Las usan index.html (calendario y disponibilidad)
// y agenda/index.html (el enlace que se manda a los artistas). Para cambiar una regla, cámbiala solo aquí.
//
// · Horario laboral: 9:00 a 17:00.
// · Cada mes tiene 3 semanas de producción: la 1.ª, 2.ª y 3.ª semana que empiezan (en lunes) en ese mes.
//   La 4.ª (y la 5.ª, si la hay) es de colchón: contratiempos y grabaciones externas (batería, etc.).
// · En una semana de producción se produce lunes-martes (bloque A) y jueves-viernes (bloque B);
//   el miércoles es para las demás áreas. Si el viernes está ocupado por una actividad externa
//   (evento tipo «externo»), el bloque B es miércoles-jueves y ese viernes solo se trabaja de 9 a 11.
// · Todos los miércoles de 9 a 12 hay oración (evento fijo).
// · Los días inhábiles (evento tipo «inhabil»: vacaciones, festivos) no se pueden agendar.
// · Tipos de producción: acústica o live = 1 bloque (2 días: 1 de grabación y ½ de mezcla y master);
//   full band = la semana completa (lun, mar, jue, vie; o lun a jue si el viernes está ocupado);
//   producción grande = 2 o más semanas completas. Cada producción guarda sus días exactos en «dias».
(function () {
  const pad = (n) => String(n).padStart(2, "0");
  const key = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const fromKey = (k) => { const [y, m, d] = String(k).split("-").map(Number); return new Date(y, m - 1, d); };
  const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
  const mondayOf = (d) => { const x = new Date(d.getFullYear(), d.getMonth(), d.getDate()); x.setDate(x.getDate() - ((x.getDay() + 6) % 7)); return x; };

  const HORARIO = { inicio: "09:00", fin: "17:00", viernesCorto: "11:00" };
  const TIPOS_PROD = {
    acustico: { n: "Acústica o live", dias: 2, desc: "2 días hábiles: 1 día de grabación y ½ día de mezcla y master." },
    fullband: { n: "Full band", dias: 5, desc: "La semana de producción completa (5 días hábiles)." },
    grande: { n: "Producción grande", dias: 10, desc: "2 semanas de producción seguidas (10 días hábiles)." },
  };
  // Fechas fijas que no se guardan en la base: siempre están
  const FIJOS = [
    { id: "fijo-oracion", titulo: "Oración", tipo: "oracion", fecha: "2026-01-07", repetir: "semanal", hora: "09:00", horaFin: "12:00", area: "general", fijo: true, excepciones: [], notas: "Todos los miércoles de 9 a 12." },
  ];

  /* Fechas en que ocurre un evento entre desde y hasta (YYYY-MM-DD, inclusive) → [{ev, ini, fin}] */
  function ocurrencias(ev, desde, hasta) {
    const out = []; if (!ev || !ev.fecha) return out;
    const ini0 = fromKey(ev.fecha), dur = ev.fin && ev.fin > ev.fecha ? Math.round((fromKey(ev.fin) - ini0) / 864e5) : 0, ex = ev.excepciones || [];
    const lim = ev.hasta && ev.hasta < hasta ? ev.hasta : hasta;
    const push = (d) => { const a = key(d), b = key(addDays(d, dur)); if (b >= desde && a <= hasta && !ex.includes(a)) out.push({ ev, ini: a, fin: b }); };
    if (!ev.repetir) { push(ini0); return out; }
    for (let n = 0; n < 3000; n++) {
      let d;
      if (ev.repetir === "semanal") d = addDays(ini0, 7 * n);
      else if (ev.repetir === "quincenal") d = addDays(ini0, 14 * n);
      else if (ev.repetir === "mensual") d = new Date(ini0.getFullYear(), ini0.getMonth() + n, ini0.getDate());
      else if (ev.repetir === "anual") d = new Date(ini0.getFullYear() + n, ini0.getMonth(), ini0.getDate());
      else break;
      if (key(d) > lim) break;
      if ((ev.repetir === "mensual" || ev.repetir === "anual") && d.getDate() !== ini0.getDate()) continue; // 31 o 29 feb en un mes que no lo tiene
      if (key(addDays(d, dur)) < desde) continue;
      push(d);
    }
    return out;
  }

  /* Días que se trabajan en una producción de inicio a fin: entre semana, y sin el miércoles cuando ese viernes
     también se produce (el miércoles es para las demás áreas). Si el viernes está ocupado, el miércoles sí entra. */
  function diasHabiles(inicio, fin) {
    const out = []; if (!inicio) return out; const f = fin && fin > inicio ? fin : inicio;
    for (let d = fromKey(inicio); key(d) <= f; d = addDays(d, 1)) {
      const w = d.getDay(); if (w === 0 || w === 6) continue;
      if (w === 3 && key(addDays(d, 2)) <= f) continue;
      out.push(key(d));
    }
    return out;
  }
  // ¿El evento ocupa ese día? (las producciones con «dias» solo ocupan esos días)
  function ocupaDia(o, d) { return o.ini <= d && o.fin >= d && (!Array.isArray(o.ev.dias) || !o.ev.dias.length || o.ev.dias.includes(d)); }
  // Semana del mes: la n-ésima semana (de lunes) que empieza en ese mes
  function semanaDelMes(lunes) { return Math.floor((fromKey(lunes).getDate() - 1) / 7) + 1; }
  function esProduccion(lunes) { return semanaDelMes(lunes) <= 3; }
  // Qué ocupa días de producción: producciones, grabaciones ligadas a una canción y días inhábiles (vacaciones, festivos)
  function ocupaProduccion(ev) { return ev.tipo === "produccion" || ev.tipo === "inhabil" || (ev.tipo === "grabacion" && !!ev.cancion_id); }
  function viernesOcupado(eventos, lunes) { const v = key(addDays(fromKey(lunes), 4)); return eventos.some((ev) => ev.tipo === "externo" && ocurrencias(ev, v, v).length); }

  /* Estado de una semana: {lunes, n (semana del mes), produccion, viernesOcupado, A:{dias, por[]}, B:{dias, por[]}} */
  function semana(eventos, lunes) {
    const l = fromKey(lunes), vo = viernesOcupado(eventos, lunes), fin = key(addDays(l, 4));
    const occ = eventos.filter(ocupaProduccion).flatMap((ev) => ocurrencias(ev, lunes, fin));
    const bloque = (offs) => { const dias = offs.map((i) => key(addDays(l, i)));
      const por = occ.filter((o) => dias.some((d) => ocupaDia(o, d))).map((o) => o.ev);
      return { dias, por: [...new Set(por)] }; };
    return { lunes, n: semanaDelMes(lunes), produccion: esProduccion(lunes), viernesOcupado: vo, A: bloque([0, 1]), B: bloque(vo ? [2, 3] : [3, 4]) };
  }

  /* Opciones para agendar un tipo de producción en la semana que empieza en lunes → [{inicio, fin, bloque, texto}] */
  function opciones(eventos, lunes, tipo) {
    const s = semana(eventos, lunes); if (!s.produccion) return [];
    const libre = (b) => !s[b].por.length;
    if (tipo === "acustico") return ["A", "B"].filter(libre).map((b) => ({ inicio: s[b].dias[0], fin: s[b].dias[1], bloque: b }));
    // Full band: la semana completa = lun, mar, jue y vie (o lun a jue si el viernes está ocupado)
    if (tipo === "fullband") return libre("A") && libre("B") ? [{ inicio: s.A.dias[0], fin: s.B.dias[1], bloque: "AB", dias: diasHabiles(s.A.dias[0], s.B.dias[1]) }] : [];
    // Producción grande: dos semanas de producción seguidas (en la app también se pueden elegir semanas sueltas)
    if (tipo === "grande") {
      const sig = key(addDays(fromKey(lunes), 7)), s2 = semana(eventos, sig);
      return libre("A") && libre("B") && s2.produccion && !s2.A.por.length && !s2.B.por.length
        ? [{ inicio: s.A.dias[0], fin: s2.B.dias[1], bloque: "2S", dias: [...diasHabiles(s.A.dias[0], s.B.dias[1]), ...diasHabiles(s2.A.dias[0], s2.B.dias[1])] }] : [];
    }
    return [];
  }
  /* Semanas desde la del día «desde» (n semanas) con sus opciones para un tipo */
  function disponibles(eventos, desde, n, tipo) {
    const l0 = mondayOf(fromKey(desde)), out = [];
    for (let i = 0; i < n; i++) { const l = key(addDays(l0, 7 * i)); out.push({ ...semana(eventos, l), opciones: opciones(eventos, l, tipo) }); }
    return out;
  }
  // ¿Choca un horario (hora–horaFin) en la fecha con la jornada de producción (9–17 en un día con producción)?
  function chocaConProduccion(eventos, fecha, hora, horaFin) {
    if (!hora) return false; const fin = horaFin || hora;
    if (!(hora < HORARIO.fin && fin > HORARIO.inicio)) return false;
    return eventos.filter(ocupaProduccion).some((ev) => ocurrencias(ev, fecha, fecha).some((o) => ocupaDia(o, fecha)));
  }

  window.AGENDA = { HORARIO, TIPOS_PROD, FIJOS, ocurrencias, semanaDelMes, esProduccion, ocupaProduccion, viernesOcupado, semana, opciones, disponibles, chocaConProduccion, diasHabiles, ocupaDia, util: { key, fromKey, addDays, mondayOf } };
})();
