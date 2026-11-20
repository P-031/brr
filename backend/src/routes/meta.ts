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
        const farmerIds = await farmerIdsForList(user, undefined);
        const [options, places, plots] = await Promise.all([
            prisma.fromOption.findMany({ orderBy: [{ group: "asc"}, { sort: "asc"}, { label: "asc" }] }),
            prisma.place.findMany(),
            farmerIds.length === 0
            ? Promise.resolve([])
            : prisma.plot.findMany({
                where: { farmerId: { in: farmerIds } },
                select: {id: true, name: true },
                orderBy: {name: "asc"},
            }),
        ]);
    
    const labels = (group: string) => options.filter((row) => row.group === group).map((row) => row.label);
    const locations : Record<string, Record<string, Record<string, string[]>>> ={};
    for (const place of places) {
        const districts = (locations[place.province] ??= {});
        const subdistricts = (districts[place.district] ??= {});
        (subdistricts[place.subdistrict] ??= []).push(place.village);
    }

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
        taskKinds: Object.keys(taskKindByName),
        cutStatuses: [...cutStatuses],
        provinces: Object.keys(locations),
        locations,
        prevPlots: plots.map((plot) => ({ code: plot.id, name: plot.name })),
    });
  }),
);