import { Router } from "express";
import { currentUser } from "../auth";
import { route } from "../http";
import { farmerIdsForList } from "../plotAccess";
import { prisma } from "../prisma";
import { taskKindByName  }  from "../serialize";
import { cutStatuses } from "../serialize";


export const metaRouter = Router();

metaRouter.get(
    "/meta/options",
    route(async (req, res) => {
        const user = currentUser(req);
        const [options, places] = await Promise.all([
            prisma.fromOption.findMany({ orderBy: [{ group: "asc"}, { sort: "asc"}, { label: "asc" }] }),
            prisma.place.findMany(),
        ]);
    
    const labels = (group: string) => options.filter((row) => row.group === group).map((row) => row.label);
    const canePlantModes = labels("canePlantModes");
    const locations : Record<string, Record<string, Record<string, string[]>>> ={};
    for (const place of places) {
        const districts = (locations[place.province] ??= {});
        const subdistricts = (districts[place.district] ??= {});
        (subdistricts[place.subdistrict] ??= []).push(place.village);
    }
    const farmerIds = await farmerIdsForList(user, undefined);
    const prevPlots = farmerIds.length === 0
      ? []
      : await prisma.plot.findMany({
          where: { farmerId: { in: farmerIds } },
          select: { id: true, name: true },
          orderBy: { updatedAt: "desc" },
          take: 300,
        });

    res.json({
        projects: labels("projects"),
        caneGroups: labels("caneGroups"),
        zones: labels("zones"),
        caneTypes: labels("caneTypes"),
        caneVarieties: labels("caneVarieties"),
        ownerships: labels("ownerships"),
        terrains: labels("terrains"),
        lossOptions: labels("lossOptions"),
        plotStatuses: labels("plotStatuses"),
        plotRequestTypes: labels("plotRequestTypes"),
        parcelStatuses: labels("parcelStatuses"),
        riskLevels: labels("riskLevels"),
        organicFertilizerTypes: labels("organicFertilizerTypes"),
        diseaseTypes: labels("diseaseTypes"),
        pestTypes: labels("pestTypes"),
        fertilizerFormulas: labels("fertilizerFormulas"),
        canePlantModes,
        caneTypesByMode: Object.fromEntries(
          canePlantModes.map((mode) => [mode, labels(`caneTypesByMode:${mode}`)]),
        ),
        projectCriteria: labels("projectCriteria").map((name) => ({
          name,
          required: false,
          options: [] as string[],
        })),
        taskKinds: Object.keys(taskKindByName),
        cutStatuses: [...cutStatuses],
        provinces: Object.keys(locations),
        locations,
        prevPlots: prevPlots.map((plot) => ({ code: plot.id, name: plot.name })),
    });
  }),
);
