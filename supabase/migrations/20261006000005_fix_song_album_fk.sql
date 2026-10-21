alter table public.songs
  drop constraint if exists songs_album_artist_fk;

alter table public.songs
  drop constraint if exists songs_album_fk;

alter table public.songs
  add constraint songs_album_fk
    foreign key (user_id, album_id)
    references public.albums(user_id, id);
