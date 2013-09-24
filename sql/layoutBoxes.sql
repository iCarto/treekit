-- {
--
-- Given a linestring and an ordered array of box data, return an array of
-- boxes placed along the given geometry.
--
-- Box data arrays meaning: dist is the distance from the end of previous box
-- (or start of line for the first element); length is the length along the
-- line of the box; width is the width of the box, hortogonal to the line.
--
-- Tree measures are expected to be in the linestring's coordinate units.
--
-- Author: Sandro Santilli <strk@vizzuality.com>
--
-- }{
CREATE OR REPLACE FUNCTION layoutBoxes(line geometry, left_side boolean, dist float8[], len float8[], width float8[], off float8[])
RETURNS geometry[] AS
$$
DECLARE
  l0 GEOMETRY; -- offsetted geometry 0
  l1 GEOMETRY; -- offsetted geometry 1
  roadrec RECORD;
  tree RECORD;
  curdst FLOAT8; -- current distance from road's start point, in meters
  f2m FLOAT8; -- foot 2 meter factor
  p0 GEOMETRY;
  p1 GEOMETRY;
  distfrac FLOAT8; -- fraction of distance along the line
  ret GEOMETRY;
  boxes GEOMETRY[];
  i INTEGER;
BEGIN


  SELECT line as geom, ST_Length(line) as len,
         CASE WHEN left_side THEN 1 ELSE -1 END as side
    INTO roadrec;

  curdst := 0;
  FOR i IN 1 .. array_upper(dist, 1)
  LOOP
    SELECT dist[i] as dist,
           len[i] as len,
           width[i] as width,
           off[i] as off
    INTO tree;

    --RAISE DEBUG 'Box % dist:% len:% width:%', i, tree.dist, tree.len, tree.width;

    curdst := curdst + tree.dist;
    distfrac := curdst/roadrec.len;
    distfrac := greatest(least(distfrac,1),0); -- warn if clamped ?
    p0 := ST_Line_Interpolate_Point(roadrec.geom, distfrac);
    curdst := curdst + tree.len;
    distfrac := curdst/roadrec.len;
    distfrac := greatest(least(distfrac,1),0); -- warn if clamped ?
    p1 := ST_Line_Interpolate_Point(roadrec.geom, distfrac);
    l0 := ST_MakeLine(p0, p1);
    BEGIN
      IF tree.off IS NOT NULL THEN
        l0 := ST_OffsetCurve(l0, tree.off*roadrec.side);
      END IF;
      l1 := ST_OffsetCurve(l0, tree.width*roadrec.side);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE WARNING 'Running OffsetCurve on line % returned %', ret, SQLERRM;
        CONTINUE;
    END;
    IF roadrec.side = 1 THEN
      ret := ST_MakeLine(l0, ST_Reverse(l1));
    ELSE
      ret := ST_MakeLine(l0, l1);
    END IF;
    ret := ST_MakeLine(ret, ST_StartPoint(l0)); -- add closing point
    ret := ST_MakePolygon(ret); -- turn into a polygon

    --RAISE DEBUG 'Box %: %', i, ST_AsEWKT(ret);

    boxes := array_append(boxes, ret);

  END LOOP;

  RETURN boxes;

END
$$
LANGUAGE 'plpgsql' IMMUTABLE STRICT;
-- }{
-- Kept for backward compatibility
CREATE OR REPLACE FUNCTION layoutBoxes(line geometry, left_side boolean, dist float8[], len float8[], width float8[])
RETURNS geometry[] AS
$$
 SELECT layoutBoxes($1, $2, $3, $4, $5, ARRAY[]::float8[]);
$$
LANGUAGE 'sql' IMMUTABLE STRICT;
-- }
