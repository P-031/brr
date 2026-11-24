import { Router } from "express";
import { currentUser } from "../auth";
import { route } from "../http";
import { prisma } from "../prisma";
import { taskKindByName  }  from "../serialize";
import { cutStatuses } from "../serialize";


export const metaRouter = Router();

metaRouter.get(
    "/meta/options",
    route(async (req, res) => {
        currentUser(req);
        const [options, places] = await Promise.all([
            prisma.fromOption.findMany({ orderBy: [{ group: "asc"}, { sort: "asc"}, { label: "asc" }] }),
            prisma.place.findMany(),
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
        prevPlots: [],
    });
  }),
);