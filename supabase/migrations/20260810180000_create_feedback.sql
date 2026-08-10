create table public.feedback_posts (
    id uuid primary key default gen_random_uuid(),
    kind text not null check (kind in ('feature', 'bug')),
    title text not null check (char_length(trim(title)) between 3 and 120),
    detail text not null check (char_length(trim(detail)) between 3 and 5000),
    status text not null default 'under_review'
        check (status in ('under_review', 'planned', 'in_progress', 'completed')),
    is_published boolean not null default true,
    vote_count integer not null default 0 check (vote_count >= 0),
    created_at timestamptz not null default now()
);

create table public.feedback_votes (
    post_id uuid not null references public.feedback_posts(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (post_id, user_id)
);

alter table public.feedback_posts enable row level security;
alter table public.feedback_votes enable row level security;

grant select on public.feedback_posts to anon, authenticated;
grant insert on public.feedback_posts to authenticated;
grant select, insert, delete on public.feedback_votes to authenticated;

create policy "Published feedback is readable"
on public.feedback_posts for select
to anon, authenticated
using (is_published = true);

create policy "Anonymous users can submit feedback"
on public.feedback_posts for insert
to authenticated
with check (
    coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false)
    and is_published = true
    and status = 'under_review'
);

create policy "Users can read their own votes"
on public.feedback_votes for select
to authenticated
using (user_id = auth.uid());

create policy "Users can vote once per post"
on public.feedback_votes for insert
to authenticated
with check (
    user_id = auth.uid()
    and exists (
        select 1
        from public.feedback_posts
        where id = post_id and is_published = true
    )
);

create policy "Users can remove their own votes"
on public.feedback_votes for delete
to authenticated
using (user_id = auth.uid());

create or replace function public.update_feedback_vote_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if tg_op = 'INSERT' then
        update public.feedback_posts
        set vote_count = vote_count + 1
        where id = new.post_id;
        return new;
    end if;

    update public.feedback_posts
    set vote_count = greatest(vote_count - 1, 0)
    where id = old.post_id;
    return old;
end;
$$;

create trigger feedback_vote_count_after_insert
after insert on public.feedback_votes
for each row execute function public.update_feedback_vote_count();

create trigger feedback_vote_count_after_delete
after delete on public.feedback_votes
for each row execute function public.update_feedback_vote_count();
