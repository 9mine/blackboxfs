implement HelloFS;

include "sys.m"; sys: Sys;
	fprint, print, fildes: import sys;
	OTRUNC, ORCLOSE, OREAD, OWRITE: import Sys;
include "styx.m"; styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";
	styxservers: Styxservers;
	Fid, Styxserver, Navigator,
	Navop, Enotfound, Enotdir: import styxservers;
include "draw.m";

trace: con 1;

HelloFS: module {
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

Qroot, Qin, Qout, Qhello, Qin_alice, Qin_bob, Qmax: con iota;
tab := array[] of {
	(Qroot, ".", Sys->DMDIR|8r555),
	(Qin, "in", Sys->DMDIR|8r555),
	(Qout, "out", Sys->DMDIR|8r555),
	(Qhello, "hello", 8r444),
};

in_tab := array[] of {
	(Qin, ".", Sys->DMDIR|8r555),
	(Qin_alice, "alice", Sys->DMDIR|8r555),
	(Qin_bob, "bob", Sys->DMDIR|8r555),
}; 

user: string;
greeting: con "Hello, World!\n";

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	styx = checkload(load Styx Styx->PATH, Styx->PATH);
	styxservers = checkload(load Styxservers Styxservers->PATH, Styxservers->PATH);
	
	user = readfile("/dev/user");
	if(user == nil)
		user = "hellofs";

	styx->init();
	styxservers->init(styx);
	styxservers->traceset(trace);

	navch := chan of ref Navop;
	spawn navigator(navch);

	nav := Navigator.new(navch);
	(tc, srv) := Styxserver.new(fildes(0), nav, big Qroot);
	servloop(tc, srv);
}

navigator(c: chan of ref Navop)
{
	loop: while(1) {
		navop := <-c;
		pick op := navop {
		Stat =>
			op.reply <-= (dir(int op.path), nil);
			
		Walk =>
			if(op.name == "..") {
				op.reply <-= (dir(Qroot), nil);
				continue loop;
			}
			case int op.path&16rff {
			Qroot =>
				for(i := 1; i < Qhello; i++) {
					if(tab[i].t1 == op.name) {
						op.reply <-= (dir(i), nil);
						continue loop;
					}
				}
			Qin =>
				op.reply <-= (dir(Qin), nil);
			* =>
				op.reply <-= (nil, Enotdir);
			}
			
		Readdir =>
			for(i := 0; i < op.count && i + op.offset < (len tab) - 1; i++) {
				op.reply <-= (dir(Qroot+1+i+op.offset), nil);
			}
			op.reply <-= (nil, nil);
		}
	}
}

servloop(tc: chan of ref Tmsg, srv: ref Styxserver)
{
	loop: while((tmsg := <-tc) != nil) {
		#sys->fprint(sys->fildes(2), "%s\n", tmsg.text());
		pick tm := tmsg {
		Open =>
			srv.default(tm);

		Read =>
			f := srv.getfid(tm.fid);
			if(f.qtype & Sys->QTDIR) {
				srv.default(tm);
				continue loop;
			}
			case int f.path {
			Qhello =>
				srv.reply(styxservers->readstr(tm, greeting));
			* =>
				srv.default(tm);
			}
		* =>
			srv.default(tmsg);
		}
	}
}

# Here are a few utility functions, not particularly required reading.

# Reads a file (or the first chunk if its contents don't fit into one read())
readfile(f: string): string
{
	fd := sys->open(f, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;
	return string buf[0:n];
}

# Given a path inside the table, this returns a Sys->Dir representing that path.
dir(path: int): ref Sys->Dir
{
	(nil, name, perm) := tab[path&16rff];
	d := ref sys->zerodir;
	d.name = name;
	d.uid = d.gid = user;
	d.qid.path = big path;
	if(perm & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mtime = d.atime = 0;
	d.mode = perm;
	if(path == Qhello)
		d.length = big len greeting;
	return d;
}

checkload[T](x: T, p: string): T
{
	if(x == nil)
		error(sys->sprint("cannot load %s: %r", p));
	return x;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

error(e: string)
{
	sys->fprint(stderr(), "hellofs: %s\n", e);
	raise "fail:error";
}
